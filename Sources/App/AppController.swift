import AppKit
import Engine
import Platform

@MainActor
final class AppController: NSObject, @MainActor EventTapDelegate {
    private var settings: AppSettings
    private let inputSources = InputSourceManager.shared
    private let eventTap = EventTap()
    private let sounds: SoundPlayer
    private var stateMachine: TypingStateMachine
    /// Храним engine (а не теряем после init): нужен для конвертации выделения —
    /// там текст уже готовый, и направление определяем по преобладающему алфавиту.
    private let engine: ConversionEngine
    private let boundaries: WordBoundaryDetector
    private let statusBar = StatusBarController()
    /// Трекер «одиночного Option» (quick-switch): срабатывание по отпусканию.
    private var aloneTracker = ModifierAloneTracker()
    /// Флаг подтверждённой смены раскладки: ставится веткой .switchLayout
    /// (результат switchLanguageAndWait), сбрасывается после .replayBuffer.
    private var confirmedSwitch = false

    /// Keycodes чистых модификаторов: Shift 0x38/0x3C, Caps 0x39, Cmd 0x37/0x36,
    /// Option 0x3A/0x3D, Ctrl 0x3B/0x3E — их keyDown'ы в буфер не идут.
    private static let pureModifierKeycodes: Set<UInt16> =
        [0x38, 0x3C, 0x39, 0x37, 0x36, 0x3A, 0x3D, 0x3B, 0x3E]

    override init() {
        settings = SettingsStore.load()
        // Раскладки по умолчанию (Russian/ABC) могут быть не включены у
        // пользователя (например, вместо Russian — RussianWin). Заменяем
        // сохранённые ID на реально включённые, если сохранённых нет в системе.
        // Через InputSourceManager.shared, а не self.inputSources: чтение
        // property до super.init() запрещено.
        let detected = InputSourceManager.shared.detectLayoutIDs()
        var resolvedRU = settings.russianLayoutID
        var resolvedEN = settings.englishLayoutID
        let enabled = InputSourceManager.shared.allLayoutIDs()
        if !enabled.contains(resolvedRU), let ru = detected.russian { resolvedRU = ru }
        if !enabled.contains(resolvedEN), let en = detected.english { resolvedEN = en }
        if resolvedRU != settings.russianLayoutID || resolvedEN != settings.englishLayoutID {
            settings.russianLayoutID = resolvedRU
            settings.englishLayoutID = resolvedEN
            SettingsStore.save(settings)
            DebugLogger.log("layouts auto-detected: ru=\(resolvedRU) en=\(resolvedEN)")
        }
        let maps = InputSourceManager.shared.makeKeycodeMaps(
            russianLayoutID: settings.russianLayoutID,
            englishLayoutID: settings.englishLayoutID)
        engine = ConversionEngine(
            russianToEnglish: CharacterPairMap(pairs: Self.buildPairs(maps.keycodeToCharRU, maps.keycodeToCharEN)),
            englishToRussian: CharacterPairMap(pairs: Self.buildPairs(maps.keycodeToCharEN, maps.keycodeToCharRU)),
            keycodeToCharRU: maps.keycodeToCharRU,
            keycodeToCharEN: maps.keycodeToCharEN)
        stateMachine = TypingStateMachine(
            settings: settings,
            engine: engine,
            checker: LayoutChecker(triggers: Self.loadSeedTriggers(), userRules: settings.userRules))
        boundaries = WordBoundaryDetector(noAutoconvertAfterTabOrEnter: settings.noAutoconvertAfterTabOrEnter)
        sounds = SoundPlayer(settings: settings)
        super.init()
        eventTap.delegate = self
        statusBar.onSwitchLayout = { [weak self] in self?.manualSwitch() }
        statusBar.onToggleAutocorrection = { [weak self] in
            guard let self else { return }
            _ = self.stateMachine.toggleAutocorrection()
            self.settings.isAutocorrectionActive = self.stateMachine.autocorrectionIsActive
            SettingsStore.save(self.settings)
        }
        statusBar.onToggleDebugLogging = { [weak self] in
            guard let self else { return }
            self.settings.debugLogging.toggle()
            DebugLogger.isEnabled = self.settings.debugLogging
            self.statusBar.setDebugLoggingOn(self.settings.debugLogging)
            SettingsStore.save(self.settings)
        }
        statusBar.onQuit = { NSApplication.shared.terminate(nil) }
        statusBar.onConvertLastWord = { [weak self] in
            guard let self else { return }
            convertOrToggle()
        }
        statusBar.onToggleAutoConversion = { [weak self] in
            guard let self else { return }
            settings.autoConvertEnabled.toggle()
            stateMachine.setAutoConvertEnabled(settings.autoConvertEnabled)
            statusBar.setAutoConversionOn(settings.autoConvertEnabled)
            SettingsStore.save(settings)
        }
        DebugLogger.isEnabled = settings.debugLogging
        statusBar.setDebugLoggingOn(settings.debugLogging)
        statusBar.setAutoConversionOn(settings.autoConvertEnabled)
    }

    func start() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            // Plan B: полноценный онбординг; MVP: предупреждение в лог
            NSLog("FreentoSwitcher: Accessibility permission not granted")
        }
        let ok = eventTap.start()
        DebugLogger.log("tap started ok=\(ok) axTrusted=\(trusted)")
    }

    func eventTap(_ tap: EventTap, didReceiveKey key: KeyEvent) -> Bool {
        // A15: исключённые приложения — bundleID фронт-процесса (MVP через NSWorkspace).
        // Проверка ДО alone-блока: иначе Option-alone в исключённом приложении
        // дойдёт до convertSelection и синтезирует туда Cmd+C/Cmd+V. Alone-трекер
        // в исключённом приложении состояние не копит значимо — просто пропускаем.
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if settings.excludedApps.contains(frontBundle) { return true }
        // Modifier-alone: Option как quick-switch (срабатывает по отпусканию,
        // без поглощения). Нужны и keyDown, и keyUp — поэтому блок ДО guard'а
        // на keyDown. Возвращаем true только на событиях самого Option: они
        // обязаны пройти в фокусное приложение, иначе модификатор «застрянет».
        // Остальные клавиши идут в обычную обработку ниже — буфер набора
        // (автоконвертация + ручная конвертация) от alone-режима не отключается.
        if settings.hotkeyConvertLastWord == .aloneOption {
            let fired = aloneTracker.handle(
                keycode: key.keycode,
                phase: key.type == .keyDown ? .down : .up,
                isTrackedModifier: { $0 == 0x3A || $0 == 0x3D }) // Option: левый/правый
            if fired {
                DebugLogger.log("hotkey option-alone hit")
                convertOrToggle()
            }
            if key.keycode == 0x3A || key.keycode == 0x3D { return true }
        }
        guard key.type == .keyDown else { return true }
        DebugLogger.log("key=0x\(String(key.keycode, radix: 16)) mods=0x\(String(key.modifiers, radix: 16)) front=\(frontBundle)")
        // A2: хоткей ручного переключения (I2: поглощаем, не отдаём системе)
        if key.keycode == settings.hotkeySwitchLayout.keycode,
           key.modifiers & 0x1C0000 == settings.hotkeySwitchLayout.modifiers & 0x1C0000 {
            DebugLogger.log("hotkey switch layout hit")
            apply(stateMachine.handleManualLayoutSwitch())
            return false
        }
        // A9: хоткей отмены конвертации
        if key.keycode == settings.hotkeyUndo.keycode,
           settings.hotkeyUndo.keycode != 0xFFFF,
           key.modifiers & 0x1C0000 == settings.hotkeyUndo.modifiers & 0x1C0000 {
            DebugLogger.log("hotkey undo hit")
            apply(stateMachine.handleUndoHotkey())
            return false
        }
        // A2-manual: хоткей принудительной конвертации последнего слова
        if key.keycode == settings.hotkeyConvertLastWord.keycode,
           settings.hotkeyConvertLastWord.keycode != 0xFFFF,
           key.modifiers & 0x1C0000 == settings.hotkeyConvertLastWord.modifiers & 0x1C0000 {
            DebugLogger.log("hotkey convert last word hit")
            convertOrToggle()
            return false
        }
        // C2: чистые keyDown'ы модификаторов не буферизуем (иначе over-delete на 1)
        if Self.pureModifierKeycodes.contains(key.keycode) { return true }
        // C2: с зажатыми Cmd/Option/Ctrl не буферизуем (Cmd+C/V не портят буфер;
        // Shift 0x20000 вне маски — заглавные буферизуются и реплеятся с флагами)
        if (key.modifiers & 0x1C0000) != 0 { return true }
        let isSep = boundaries.isWordSeparator(
            key.keycode, englishLayout: !inputSources.isCurrentRussian())
        if isSep {
            DebugLogger.log(
                "sep: layout=\(inputSources.currentLayoutID())"
                    + " isRussian=\(inputSources.isCurrentRussian())")
        }
        apply(stateMachine.handleKeyDown(
            KeyStroke(keycode: key.keycode, modifiers: key.modifiers), isSeparator: isSep,
            currentLayoutIsRussian: inputSources.isCurrentRussian()))
        return true
    }

    private func manualSwitch() {
        apply(stateMachine.handleManualLayoutSwitch())
    }

    /// Общий обработчик хоткея конвертации. Word-путь (backspace'ы + реплей)
    /// безопасен только при пустом выделении: выделение мышкой не генерирует
    /// клавиш, поэтому наш буфер набора может быть непустым ПРИ активном
    /// выделении — backspace съест выделение + текст перед ним. Маршрутизация:
    /// выделение есть → конвертация выделения; нет → word-путь; AX молчит →
    /// clipboard-probe, не нашёл текст → word-путь.
    private func convertOrToggle() {
        let isRussian = inputSources.isCurrentRussian()
        switch SelectionProbe.hasSelection() {
        case .some(true):
            DebugLogger.log("probe: selection=true")
            // AX говорит выделение есть, но копирование не удалось —
            // НЕ лезем в word path (деструктивно). Просто ничего.
            if let sel = Clipboard.grabSelection() { convertSelection(sel) }
        case .some(false):
            DebugLogger.log("probe: selection=false")
            apply(stateMachine.handleManualConvert(currentLayoutIsRussian: isRussian))
        case .none:
            DebugLogger.log("probe: selection=unknown, clipboard fallback")
            if let sel = Clipboard.grabSelection() {
                convertSelection(sel)
            } else {
                apply(stateMachine.handleManualConvert(currentLayoutIsRussian: isRussian))
            }
        }
    }

    /// Последняя конвертация выделения: (оригинал, сконвертированное).
    /// Повторный хоткей при том же выделении откатывает обратно (Punto-style).
    private var lastSelection: (original: String, converted: String)?

    private func convertSelection(_ sel: (copied: String, snapshot: PasteboardSnapshot)) {
        // Откат: выделение — это ровно то, что мы сконвертировали в прошлый раз.
        if let pair = lastSelection, sel.copied == pair.converted {
            Clipboard.paste(pair.original)
            usleep(300_000) // вставка успела прочитать буфер — вернём пользователю снапшот
            Clipboard.restore(sel.snapshot)
            reselect(count: pair.original.count)
            lastSelection = (original: pair.converted, converted: pair.original)
            sounds.play(.selectionConvert, switchingToRussian: true) // направление не критично
            return
        }
        // Выделение без букв — вставки ещё не было, буфер возвращаем сразу (sleep не нужен).
        guard let mode = engine.conversionMode(for: sel.copied) else {
            Clipboard.restore(sel.snapshot)
            return
        }
        let converted = engine.convert(sel.copied, mode: mode)
        // Буквы не маппятся RU↔EN — вставки ещё не было, буфер возвращаем сразу (sleep не нужен).
        guard converted != sel.copied else {
            Clipboard.restore(sel.snapshot)
            return
        }
        Clipboard.paste(converted)
        usleep(300_000) // вставка успела прочитать буфер — вернём пользователю снапшот
        Clipboard.restore(sel.snapshot)
        reselect(count: converted.count)
        lastSelection = (original: sel.copied, converted: converted)
        sounds.play(.selectionConvert, switchingToRussian: mode == .toRussian)
        // Раскладку системы приводим в соответствие с результатом (как Punto).
        inputSources.selectLayout(russian: mode == .toRussian,
                                  russianLayoutID: settings.russianLayoutID,
                                  englishLayoutID: settings.englishLayoutID)
    }

    /// Выделяет вставленный текст заново: Shift+Left ×N (Punto-style,
    /// чтобы повторное нажатие хоткея переводило тот же кусок обратно).
    private func reselect(count: Int) {
        for _ in 0..<min(count, 200) {
            EventSynth.pressKey(0x7B, flags: [.maskShift]) // стрелка влево
        }
    }

    private func apply(_ effects: [EngineEffect]) {
        DebugLogger.log("effects: \(effects.map { String(describing: $0) })")
        for e in effects {
            switch e {
            case .switchLayout:
                confirmedSwitch = inputSources.switchLanguageAndWait(
                    russianLayoutID: settings.russianLayoutID,
                    englishLayoutID: settings.englishLayoutID)
                DebugLogger.log("switchLayout confirmed=\(confirmedSwitch)")
            case .playSound(let mask):
                sounds.play(mask, switchingToRussian: inputSources.isCurrentRussian())
            case .deleteCharacters(let count):
                for _ in 0..<count { EventSynth.pressKey(0x33) }
            case .replayBuffer(let strokes, let word):
                // Keycode-реплей после подтверждённой смены раскладки:
                // unicode-постинг (postText) Заметки/Терминал игнорируют.
                if confirmedSwitch {
                    for s in strokes {
                        EventSynth.pressKey(s.keycode, flags: CGEventFlags(rawValue: s.modifiers & 0x1C0000))
                    }
                } else {
                    // Fallback: unicode-постинг (некоторые приложения его не принимают,
                    // но лучше, чем ничего).
                    EventSynth.postText(word)
                }
                confirmedSwitch = false
            case .resetBuffers: break
            case .toggleAutocorrection: break
            case .none: break
            }
        }
    }

    private static func buildPairs(_ from: [UInt16: Character], _ to: [UInt16: Character]) -> [Character: Character] {
        var pairs: [Character: Character] = [:]
        for (kc, dst) in to {
            if let src = from[kc], src != dst { pairs[src] = dst }
        }
        return pairs
    }

    private static func loadSeedTriggers() -> [String] {
        // App-таргет без ресурсов: seed-файл копируется в Contents/Resources
        // скриптом Scripts/package-app.sh, поэтому читаем через Bundle.main.
        guard let url = Bundle.main.url(forResource: "seed-triggers", withExtension: "txt"),
              let s = try? String(contentsOf: url) else { return [] }
        return s.split(separator: "\n").map(String.init)
    }
}

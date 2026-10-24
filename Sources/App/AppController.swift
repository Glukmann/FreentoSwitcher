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
    private let boundaries: WordBoundaryDetector
    private let statusBar = StatusBarController()

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
        let engine = ConversionEngine(
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
        DebugLogger.isEnabled = settings.debugLogging
        statusBar.setDebugLoggingOn(settings.debugLogging)
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
        guard key.type == .keyDown else { return true }
        // A15: исключённые приложения — сравнение bundleID фронт-процесса (MVP через NSWorkspace)
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        DebugLogger.log("key=0x\(String(key.keycode, radix: 16)) mods=0x\(String(key.modifiers, radix: 16)) front=\(frontBundle)")
        if settings.excludedApps.contains(frontBundle) { return true }
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

    private func apply(_ effects: [EngineEffect]) {
        DebugLogger.log("effects: \(effects.map { String(describing: $0) })")
        for e in effects {
            switch e {
            case .switchLayout:
                inputSources.switchLanguage(
                    russianLayoutID: settings.russianLayoutID,
                    englishLayoutID: settings.englishLayoutID)
            case .playSound(let mask):
                sounds.play(mask, switchingToRussian: inputSources.isCurrentRussian())
            case .deleteCharacters(let count):
                for _ in 0..<count { EventSynth.pressKey(0x33) }
            case .replayBuffer(let strokes, let word):
                // Реплей готовой строкой: keycode-реплей гонялся со сменой
                // раскладки (первый символ вставал в старой). strokes сохранены
                // в эффекте — запасной путь, если unicode-постинг даст сбои.
                EventSynth.postText(word)
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

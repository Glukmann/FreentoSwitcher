import AppKit
import Engine
import Platform

@MainActor
final class AppController: NSObject, @MainActor EventTapDelegate {
    private let settings: AppSettings
    private let inputSources = InputSourceManager.shared
    private let eventTap = EventTap()
    private let sounds: SoundPlayer
    private var stateMachine: TypingStateMachine
    private let boundaries: WordBoundaryDetector
    private let statusBar = StatusBarController()

    override init() {
        settings = SettingsStore.load()
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
            _ = self?.stateMachine.toggleAutocorrection()
        }
        statusBar.onQuit = { NSApplication.shared.terminate(nil) }
    }

    func start() {
        if !AXIsProcessTrusted() {
            // Plan B: полноценный онбординг; MVP: предупреждение в лог
            NSLog("FreentoSwitcher: Accessibility permission not granted")
        }
        _ = eventTap.start()
    }

    func eventTap(_ tap: EventTap, didReceiveKey key: KeyEvent) -> Bool {
        guard key.type == .keyDown else { return true }
        // A15: исключённые приложения — сравнение bundleID фронт-процесса (MVP через NSWorkspace)
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if settings.excludedApps.contains(frontBundle) { return true }
        // A2: хоткей ручного переключения
        if key.keycode == settings.hotkeySwitchLayout.keycode,
           key.modifiers & 0x1C0000 == settings.hotkeySwitchLayout.modifiers & 0x1C0000 {
            apply(stateMachine.handleManualLayoutSwitch())
            return true
        }
        // A9: хоткей отмены конвертации
        if key.keycode == settings.hotkeyUndo.keycode,
           settings.hotkeyUndo.keycode != 0xFFFF,
           key.modifiers & 0x1C0000 == settings.hotkeyUndo.modifiers & 0x1C0000 {
            apply(stateMachine.handleUndoHotkey())
            return true
        }
        let isSep = boundaries.isWordSeparator(key.keycode)
        apply(stateMachine.handleKeyDown(
            KeyStroke(keycode: key.keycode, modifiers: key.modifiers), isSeparator: isSep,
            currentLayoutIsRussian: inputSources.isCurrentRussian()))
        return true
    }

    private func manualSwitch() {
        apply(stateMachine.handleManualLayoutSwitch())
    }

    private func apply(_ effects: [EngineEffect]) {
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
            case .replayBuffer(let strokes):
                for s in strokes { EventSynth.pressKey(s.keycode) }
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

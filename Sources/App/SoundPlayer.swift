import AppKit
import Engine

@MainActor
final class SoundPlayer {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func play(_ sound: SoundMask, switchingToRussian: Bool) {
        guard settings.isSoundOn, settings.sounds.contains(sound) else { return }
        let name: String
        switch sound {
        case .switchToRussian: name = switchingToRussian ? "Tink" : "Pop"
        case .switchToEnglish: name = switchingToRussian ? "Pop" : "Tink"
        case .autoConvert: name = "Hero"
        case .undo: name = "Funk"
        case .selectionConvert: name = "Hero"
        default: name = "Tink"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

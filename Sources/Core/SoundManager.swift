import AppKit

enum SoundManager {
    @MainActor
    static func playCopySound() {
        AppState.shared.copySound.play()
    }

    static func playPasteSound() {
        NSSound(named: "Pop")?.play()
    }
}

import AppKit

enum SoundManager {
    static func playCopySound() {
        NSSound(named: "Tink")?.play()
    }

    static func playPasteSound() {
        NSSound(named: "Pop")?.play()
    }
}

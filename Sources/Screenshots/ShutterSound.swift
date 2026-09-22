import AppKit

@MainActor
enum ShutterSound {
    private static let sound: NSSound? = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true
    ) ?? NSSound(named: "Grab")

    static func play() {
        sound?.stop()
        sound?.play()
    }
}

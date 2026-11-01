import AppKit

/// Plays the short sound for a session alarm.
final class Chime {
    static let soundName = NSSound.Name("Glass")

    /// Held so the sound is not deallocated mid-playback.
    private let sound = NSSound(named: soundName)

    func play() {
        guard let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}

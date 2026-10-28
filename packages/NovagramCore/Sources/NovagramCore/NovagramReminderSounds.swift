import AppKit

// Unread reminder tones, copied from the iOS UnreadReminder module (same `unread_reminder_sound` keys).
public enum NovagramReminderSounds {
    public static let options = ["default", "chime", "glass", "bell", "note", "tritone", "marimba", "crystal", "droplet", "ping", "pulse", "harp", "signal", "none"]

    private static var player: NSSound?

    public static func url(for key: String) -> URL? {
        return Bundle.module.url(forResource: key, withExtension: "caf", subdirectory: "ReminderSounds")
    }

    // "default" plays the system alert sound, "none" plays nothing.
    public static func play(_ key: String) {
        player?.stop()
        player = nil
        switch key {
        case "none":
            break
        case "default":
            NSSound.beep()
        default:
            guard let url = url(for: key) else {
                return
            }
            let sound = NSSound(contentsOf: url, byReference: true)
            sound?.play()
            player = sound
        }
    }
}

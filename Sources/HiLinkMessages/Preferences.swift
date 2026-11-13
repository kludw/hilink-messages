import Foundation

/// User settings, stored in the app's preferences. The Settings window edits them with
/// `@AppStorage` under the same keys; the rest of the app reads them here.
enum Preferences {
    enum Key {
        static let pollInterval = "pollInterval"
        static let playsSound = "playsSound"
        static let tone = "tone"
        static let showsNotifications = "showsNotifications"
        static let keepsRunningInMenuBar = "keepsRunningInMenuBar"
    }

    /// How often the stick can be checked for new messages, in seconds.
    static let pollIntervals = [2, 5, 10, 30]

    /// Call once at launch, before anything reads a setting.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.pollInterval: 5,
            Key.playsSound: true,
            Key.tone: Tone.note.rawValue,
            Key.showsNotifications: true,
            Key.keepsRunningInMenuBar: true,
        ])
    }

    static var pollInterval: Int {
        let value = UserDefaults.standard.integer(forKey: Key.pollInterval)
        return pollIntervals.contains(value) ? value : 5
    }

    static var playsSound: Bool { UserDefaults.standard.bool(forKey: Key.playsSound) }
    static var showsNotifications: Bool { UserDefaults.standard.bool(forKey: Key.showsNotifications) }
    static var keepsRunningInMenuBar: Bool { UserDefaults.standard.bool(forKey: Key.keepsRunningInMenuBar) }

    static var tone: Tone {
        Tone(rawValue: UserDefaults.standard.string(forKey: Key.tone) ?? "") ?? .note
    }
}

/// The text tones that ship with macOS (the same ones an iPhone uses).
enum Tone: String, CaseIterable, Identifiable {
    case note, triTone, received

    var id: String { rawValue }

    var name: String {
        switch self {
        case .note: "Note"
        case .triTone: "Tri-tone"
        case .received: "Received"
        }
    }

    private var file: String {
        switch self {
        case .note: "Modern/Note.m4r"
        case .triTone: "Classic/Tri-Tone.m4r"
        case .received: "ReceivedMessage.caf"
        }
    }

    /// The tone's sound file, or nil if this version of macOS does not include it.
    var url: URL? {
        let folder = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/"
        let url = URL(fileURLWithPath: folder + file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The tones that can actually be played on this Mac.
    static var available: [Tone] { allCases.filter { $0.url != nil } }
}

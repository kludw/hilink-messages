import AVFoundation
import AppKit
import UserNotifications

/// Plays the incoming-message tone and posts a notification when the app is in the background.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called with a conversation id when the user clicks a notification.
    var onOpenConversation: ((String) -> Void)?

    private var player: AVAudioPlayer?

    private nonisolated static let codeCategory = "verification-code"
    private nonisolated static let copyCodeAction = "copy-code"

    /// Asks for permission to show notifications. Safe to call on every launch.
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Messages carrying a verification code get a "Copy Code" button on their banner.
        let copy = UNNotificationAction(identifier: Self.copyCodeAction, title: "Copy Code", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.codeCategory, actions: [copy], intentIdentifiers: [])
        ])
        _ = try? await center.requestAuthorization(options: [.alert, .badge])
    }

    /// Plays the tone chosen in Settings, or the first available one, or a beep.
    func playTone() {
        let tone = Preferences.tone.url != nil ? Preferences.tone : Tone.available.first
        if let url = tone?.url, let player = try? AVAudioPlayer(contentsOf: url) {
            self.player = player
            player.play()
        } else {
            NSSound.beep()
        }
    }

    private static var previewPlayer: AVAudioPlayer?

    /// Plays a tone once, for choosing one in Settings.
    static func preview(_ tone: Tone) {
        guard let url = tone.url, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        previewPlayer = player
        player.play()
    }

    /// Shows a banner for a received message. The tone is played separately, so the banner is silent.
    func notify(title: String, text: String, conversationID: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        content.threadIdentifier = conversationID
        content.userInfo = ["conversation": conversationID]
        if let code = MessageText.verificationCode(in: text) {
            content.categoryIdentifier = Self.codeCategory
            content.userInfo["code"] = code
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let id = info["conversation"] as? String
        let code = info["code"] as? String
        let wantsCopy = response.actionIdentifier == Self.copyCodeAction
        await MainActor.run {
            if wantsCopy, let code {
                // Copy quietly; the app stays in the background.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } else if let id {
                onOpenConversation?(id)
            }
        }
    }
}

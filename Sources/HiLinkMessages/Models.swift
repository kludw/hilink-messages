import Foundation

struct Message: Identifiable, Hashable {
    enum Status: Hashable {
        case sending, sent, failed
    }

    var id: String
    var text: String
    var date: Date
    var isOutgoing: Bool
    var status: Status = .sent
}

struct Conversation: Identifiable, Hashable {
    /// Stable across reloads: derived from the phone number, so "+44 7700…" and "07700…" share a thread.
    let id: String
    /// Phone number or alphanumeric sender ID (e.g. "O2UK").
    var number: String
    /// Contact name, if the number matches a contact.
    var name: String?
    /// Contact photo, if the number matches a contact that has one.
    var avatarData: Data?
    var messages: [Message] = []
    var hasUnread = false

    init(number: String) {
        id = Self.id(for: number)
        self.number = number
    }

    static func id(for number: String) -> String {
        ContactsDirectory.key(for: number) ?? number.lowercased()
    }

    var title: String { name ?? number }
    var lastMessage: Message? { messages.last }
    /// A thread with no messages yet is a new one being started, so it sorts to the top.
    var lastDate: Date { lastMessage?.date ?? .distantFuture }

    var initials: String? { name.flatMap(Self.initials(for:)) }

    static func initials(for name: String) -> String? {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }
}

struct ModemStatus {
    var isConnected: Bool
    var simReady = true
    /// False when the stick has no mobile signal.
    var hasService = true
    var carrier = ""
    var network = ""
    /// 0...5
    var signalBars = 0
    /// The SIM's own number: reported by the SIM, or else the one saved by the user for this SIM.
    var phoneNumber: String?
    /// False when the SIM itself reports the number, so there is nothing to edit.
    var canEditNumber = false
    var simID: String?
    /// The SIM's home country, used to prefill the dialling code.
    var simCountry: Country?

    /// The app can only be used with the stick connected and a working SIM in it.
    var isUsable: Bool { isConnected && simReady && hasService }

    /// Model name and firmware version, for the Settings window.
    var deviceName = ""
    var firmware = ""

    /// Messages stored on the stick, and how many it can hold (0 until known).
    var storedMessages = 0
    var storageCapacity = 0

    /// Above 80% full it is time to delete something: a full stick cannot receive new messages.
    var isStorageNearlyFull: Bool { storageCapacity > 0 && storedMessages * 5 >= storageCapacity * 4 }
    var isStorageFull: Bool { storageCapacity > 0 && storedMessages >= storageCapacity }

    /// One line describing the connection: the carrier and network, or what is missing.
    var summary: String {
        if !isConnected { return "Stick not connected" }
        if !simReady { return "No SIM" }
        if !hasService { return "No signal" }
        return [carrier, network].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static let disconnected = ModemStatus(isConnected: false)
}

enum SMSCounter {
    /// Returns (characters used, characters available across the current number of segments, segments).
    static func count(_ text: String) -> (used: Int, capacity: Int, segments: Int) {
        let scalars = text.unicodeScalars
        let isGSM = scalars.allSatisfy { gsmCharacters.contains($0) || gsmExtended.contains($0) }
        // In the GSM alphabet the extension characters (€, brackets, …) take two places each.
        let used = isGSM ? scalars.reduce(0) { $0 + (gsmExtended.contains($1) ? 2 : 1) } : text.utf16.count
        let single = isGSM ? 160 : 70
        let multi = isGSM ? 153 : 67
        if used <= single { return (used, single, 1) }
        let segments = Int((Double(used) / Double(multi)).rounded(.up))
        return (used, segments * multi, segments)
    }

    private static let gsmExtended = CharacterSet(charactersIn: "^{}\\[~]|€")
    private static let gsmCharacters = CharacterSet(charactersIn:
        "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?"
        + "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
    )
}

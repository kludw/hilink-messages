import Foundation
import SwiftUI

/// App state: conversations built from the messages stored on the stick, plus anything still being sent.
@MainActor
@Observable
final class MessageStore {
    /// The one store for the app; it runs for as long as the app does, with or without a window.
    static let shared = MessageStore()

    private(set) var conversations: [Conversation] = []
    var selection: Conversation.ID? {
        didSet {
            // Leaving a thread that was started but never used discards it.
            if let draftNumber, selection != Conversation.id(for: draftNumber) {
                self.draftNumber = nil
                rebuild()
            }
            // Selecting a thread any other way than ⌘- or ⇧-click makes it the only selected one.
            if let selection {
                if !selectedIDs.contains(selection) { selectedIDs = [selection] }
            } else {
                selectedIDs = []
            }
        }
    }
    /// Every highlighted thread. More than one only after ⌘- or ⇧-clicking in the sidebar;
    /// `selection` is then the anchor and no single thread is shown.
    private(set) var selectedIDs: Set<Conversation.ID> = []
    /// Threads awaiting the "delete?" confirmation.
    var pendingDeletion: Set<Conversation.ID> = []
    var isComposingNew = false
    var searchText = ""
    var showsUnreadOnly = false
    private(set) var modem = ModemStatus.disconnected

    /// Launch with `--sample-data` to work on the UI without the stick.
    private let usesSampleData = CommandLine.arguments.contains("--sample-data")
    private var client: ModemClient?
    private var modemMessages: [ModemSMS] = []
    private var pending: [PendingMessage] = []
    private var lastCounts: SMSCounts?
    private var failedPolls = 0
    private var noServicePolls = 0
    private var contacts: [String: ContactInfo] = [:]
    private var contactEntries: [ContactEntry] = []
    /// Number of a thread opened from New Message that has no messages yet.
    private var draftNumber: String?
    private let notifier = Notifier()
    /// Indexes of the received messages seen so far; nil until the first load, so old messages stay quiet.
    private var knownInbox: Set<Int>?

    /// An outgoing message that is not (yet) in the stick's outbox.
    private struct PendingMessage {
        let id = UUID().uuidString
        var number: String
        var text: String
        var date = Date.now
        var status = Message.Status.sending
    }

    // MARK: Derived lists

    var sortedConversations: [Conversation] {
        conversations.sorted { $0.lastDate > $1.lastDate }
    }

    var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let base = showsUnreadOnly ? sortedConversations.filter(\.hasUnread) : sortedConversations
        guard !query.isEmpty else { return base }
        return base.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.number.localizedCaseInsensitiveContains(query)
                || conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    func conversation(_ id: Conversation.ID?) -> Conversation? {
        conversations.first { $0.id == id }
    }

    // MARK: Lifecycle

    private var hasStarted = false

    /// Starts the background work once; it keeps running after the window is closed.
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await start() }
    }

    /// Loads contacts, then keeps the stick's status and messages up to date.
    private func start() async {
        notifier.onOpenConversation = { [weak self] id in
            self?.isComposingNew = false
            self?.selection = id
            MainWindow.show()
        }
        // Ask for every permission up front, one prompt after the other.
        Task {
            await notifier.requestPermission()
            await loadContacts()
        }

        if usesSampleData {
            modemMessages = SampleData.messages
            modem = ModemStatus(isConnected: true, carrier: "Carrier", network: "LTE", signalBars: 4,
                                phoneNumber: "+48 600 100 200", deviceName: "Sample stick",
                                firmware: "0.0", storageCapacity: 500)
            modem.storedMessages = CommandLine.arguments.contains("--storage-nearly-full") ? 450 : modemMessages.count
            rebuild()
            selection = sortedConversations.first?.id
            return
        }

        while !Task.isCancelled {
            await poll()
            // Between polls, watch for the stick's network interface vanishing: that is
            // how an unplugged stick shows up, within a second, without waiting on a timeout.
            let pause = client == nil ? 2 : Preferences.pollInterval
            for _ in 0..<(pause * 2) {
                try? await Task.sleep(for: .milliseconds(500))
                if let client, !client.isReachableLocally {
                    disconnect()
                    break
                }
            }
        }
    }

    private func disconnect() {
        client = nil
        lastCounts = nil
        failedPolls = 0
        noServicePolls = 0
        modem = .disconnected
        isComposingNew = false
    }

    private func poll() async {
        // Developer aids for looking at the blocked states without unplugging anything.
        if CommandLine.arguments.contains("--no-modem") {
            modem = .disconnected
            return
        }
        if let client, !client.isReachableLocally { disconnect() }
        if client == nil { client = await ModemClient.discover() }
        guard let client else {
            modem = .disconnected
            return
        }
        do {
            let info = try await client.info()
            let (stored, capacity) = (modem.storedMessages, modem.storageCapacity)
            modem = ModemStatus(isConnected: true, simReady: info.simReady, carrier: info.carrier,
                                network: info.network, signalBars: info.signalBars,
                                phoneNumber: info.phoneNumber ?? savedNumber(simID: info.simID),
                                canEditNumber: info.phoneNumber == nil, simID: info.simID,
                                simCountry: info.simCountry,
                                deviceName: info.deviceName, firmware: info.firmware,
                                storedMessages: stored, storageCapacity: capacity)
            if CommandLine.arguments.contains("--no-sim") { modem.simReady = false }
            failedPolls = 0
            // Signal comes and goes; only two readings in a row without service block the app.
            let hasService = info.hasService && !CommandLine.arguments.contains("--no-signal")
            noServicePolls = hasService ? 0 : noServicePolls + 1
            modem.hasService = noServicePolls < 2
            if !modem.isUsable { isComposingNew = false }
            let counts = try await client.counts()
            modem.storedMessages = counts.stored
            modem.storageCapacity = counts.capacity
            // Developer aid: pretend the stick is 90% full, to look at the storage warning.
            if CommandLine.arguments.contains("--storage-nearly-full") {
                modem.storedMessages = counts.capacity * 9 / 10
            }
            if counts != lastCounts {
                modemMessages = try await client.messages()
                lastCounts = counts
                rebuild()
                if selection == nil, !isComposingNew { selection = sortedConversations.first?.id }
                announceNewMessages()
                if NSApp.isActive, selectedIDs.count <= 1 { markRead(selection) }
            }
        } catch {
            // One failed request can be a hiccup; two in a row means the stick is gone or restarting.
            failedPolls += 1
            guard failedPolls >= 2 else { return }
            // Drop the client so the next poll rediscovers it.
            disconnect()
        }
    }

    /// Plays the tone for messages that arrived since the last load, and posts a banner
    /// for each one if the app is in the background.
    private func announceNewMessages() {
        let received = modemMessages.filter { !$0.isOutgoing }
        defer { knownInbox = Set(received.compactMap(\.index)) }
        guard let knownInbox else { return }
        let fresh = received.filter { sms in sms.isUnread && sms.index.map { !knownInbox.contains($0) } == true }
        guard !fresh.isEmpty else { return }

        if Preferences.playsSound { notifier.playTone() }
        guard Preferences.showsNotifications, !NSApp.isActive else { return }
        for sms in fresh.sorted(by: { $0.date < $1.date }) {
            let id = Conversation.id(for: sms.phone)
            notifier.notify(title: conversation(id)?.title ?? sms.phone, text: sms.content, conversationID: id)
        }
    }

    private func loadContacts() async {
        let snapshot = await ContactsDirectory.load()
        contacts = snapshot.index
        contactEntries = snapshot.entries
        rebuild()
    }

    /// Regroups the stick's messages and pending sends into conversations.
    private func rebuild() {
        var groups: [String: Conversation] = [:]
        func add(_ message: Message, number: String, isUnread: Bool) {
            var conversation = groups[Conversation.id(for: number)] ?? Conversation(number: number)
            conversation.messages.append(message)
            if isUnread { conversation.hasUnread = true }
            groups[conversation.id] = conversation
        }

        for (offset, sms) in modemMessages.enumerated() {
            let id = sms.index.map { "\(sms.isOutgoing ? "out" : "in")-\($0)" } ?? "sample-\(offset)"
            add(Message(id: id, text: sms.content, date: sms.date, isOutgoing: sms.isOutgoing,
                        status: sms.hasFailed ? .failed : .sent),
                number: sms.phone, isUnread: sms.isUnread)
        }
        for item in pending {
            add(Message(id: item.id, text: item.text, date: item.date, isOutgoing: true, status: item.status),
                number: item.number, isUnread: false)
        }

        if let draftNumber, groups[Conversation.id(for: draftNumber)] == nil {
            groups[Conversation.id(for: draftNumber)] = Conversation(number: draftNumber)
        }

        conversations = groups.values.map { group in
            var conversation = group
            conversation.messages.sort { $0.date < $1.date }
            if let key = ContactsDirectory.key(for: conversation.number), let contact = contacts[key] {
                conversation.name = contact.name
                conversation.avatarData = contact.imageData
            }
            return conversation
        }
        // A thread deleted elsewhere (or emptied by a reload) cannot stay selected.
        selectedIDs.formIntersection(groups.keys)
    }

    // MARK: Own number

    private func numberKey(simID: String?) -> String { "ownNumber." + (simID ?? "unknown") }

    private func savedNumber(simID: String?) -> String? {
        UserDefaults.standard.string(forKey: numberKey(simID: simID))
    }

    /// Remembers the SIM's phone number, for SIMs that do not report their own. Empty clears it.
    func setOwnNumber(_ number: String) {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        let key = numberKey(simID: modem.simID)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
        modem.phoneNumber = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Actions

    /// A click on a sidebar row. ⌘ toggles the row, ⇧ extends from the anchor, a plain click selects only it.
    func select(_ id: Conversation.ID, command: Bool, shift: Bool) {
        if shift, let anchor = selection {
            let order = filteredConversations.map(\.id)
            if let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
                selectedIDs = Set(order[min(from, to)...max(from, to)])
                return
            }
        }
        if command {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
                if selection == id { selection = selectedIDs.first }
            } else {
                selectedIDs.insert(id)
                selection = id
            }
            return
        }
        selectedIDs = [id]
        selection = id
    }

    /// Asks to delete the clicked thread, or the whole multi-selection if the click was inside it.
    func requestDelete(_ id: Conversation.ID) {
        pendingDeletion = selectedIDs.count > 1 && selectedIDs.contains(id) ? selectedIDs : [id]
    }

    func requestDeleteSelection() {
        pendingDeletion = selectedIDs
    }

    func delete(_ ids: Set<Conversation.ID>) {
        for id in ids { delete(id) }
    }

    func startNewMessage() {
        guard modem.isUsable else { return }
        selection = nil
        isComposingNew = true
    }

    func markRead(_ id: Conversation.ID?) {
        guard let id else { return }
        var indexes: [Int] = []
        for offset in modemMessages.indices
        where modemMessages[offset].isUnread && Conversation.id(for: modemMessages[offset].phone) == id {
            modemMessages[offset].isUnread = false
            if let index = modemMessages[offset].index { indexes.append(index) }
        }
        guard conversation(id)?.hasUnread == true else { return }
        rebuild()
        guard let client else { return }
        Task {
            for index in indexes { try? await client.markRead(index: index) }
        }
    }

    func send(_ text: String, in id: Conversation.ID) {
        guard let number = conversation(id)?.number else { return }
        send(text, number: number)
    }

    /// Contacts and existing threads matching what was typed into the "To:" field.
    func recipientSuggestions(for query: String) -> [ContactEntry] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let digits = typed.filter { $0.isASCII && $0.isNumber }
        func matches(name: String, number: String) -> Bool {
            name.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || (digits.count >= 2 && number.filter { $0.isASCII && $0.isNumber }.contains(digits))
        }

        var seen = Set<String>()
        var result: [ContactEntry] = []
        for entry in contactEntries where matches(name: entry.name, number: entry.number) {
            if seen.insert(Conversation.id(for: entry.number)).inserted { result.append(entry) }
        }
        // Threads with numbers or senders that are not in Contacts.
        for conversation in sortedConversations
        where matches(name: conversation.title, number: conversation.number) && !seen.contains(conversation.id) {
            seen.insert(conversation.id)
            result.append(ContactEntry(name: conversation.title, number: conversation.number,
                                       label: nil, imageData: conversation.avatarData))
        }

        func startsWithQuery(_ entry: ContactEntry) -> Bool {
            entry.name.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
        let ranked = result.filter(startsWithQuery) + result.filter { !startsWithQuery($0) }
        return Array(ranked.prefix(30))
    }

    /// Opens the thread for a number, starting an empty one if there are no messages with it yet.
    func openConversation(number: String) {
        let id = Conversation.id(for: number)
        if conversation(id) == nil {
            draftNumber = number
            rebuild()
        }
        isComposingNew = false
        selection = id
    }

    /// Sends to whatever was typed into the "To:" field: a number, or the name of a contact or thread.
    func send(_ text: String, to recipient: String) {
        let typed = recipient.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        let named = recipientSuggestions(for: typed).first { $0.name.caseInsensitiveCompare(typed) == .orderedSame }
        let number = named?.number ?? typed
        guard send(text, number: number) else { return }
        isComposingNew = false
        selection = Conversation.id(for: number)
    }

    @discardableResult
    private func send(_ text: String, number: String) -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        let item = PendingMessage(number: number, text: body)
        pending.append(item)
        rebuild()
        let outboxBefore = Set(modemMessages.filter(\.isOutgoing).compactMap(\.index))

        Task {
            var outcome = Message.Status.sent
            if CommandLine.arguments.contains("--fail-sends") {
                // Developer aid: every send fails, to look at the failed state and retry.
                try? await Task.sleep(for: .milliseconds(700))
                outcome = .failed
            } else if let client {
                do {
                    try await client.send(body, to: Self.dialable(number))
                } catch {
                    outcome = .failed
                }
                if let reloaded = try? await client.messages() {
                    modemMessages = reloaded
                    lastCounts = nil
                }
            } else if usesSampleData {
                try? await Task.sleep(for: .milliseconds(700))
            } else {
                outcome = .failed
            }

            // Once the stick has the message in its outbox, that copy replaces the pending one.
            // It is recognised as an outbox entry that was not there before, so an earlier
            // message with the same text is not mistaken for it.
            let isStored = modemMessages.contains { sms in
                sms.isOutgoing && sms.content == body && sms.index.map { !outboxBefore.contains($0) } == true
                    && Conversation.id(for: sms.phone) == Conversation.id(for: number)
            }
            if isStored {
                pending.removeAll { $0.id == item.id }
            } else if let offset = pending.firstIndex(where: { $0.id == item.id }) {
                pending[offset].status = outcome
            }
            rebuild()
        }
        return true
    }

    /// Sends a failed message again. The failed copy is replaced by the new attempt.
    func retry(_ messageID: Message.ID, in id: Conversation.ID) {
        guard let conversation = conversation(id),
              let message = conversation.messages.first(where: { $0.id == messageID }),
              message.isOutgoing, message.status == .failed else { return }

        if let offset = pending.firstIndex(where: { $0.id == messageID }) {
            // It never reached the stick's outbox.
            pending.remove(at: offset)
        } else if messageID.hasPrefix("out-"), let index = Int(messageID.dropFirst(4)) {
            // The stick kept a failed copy in its outbox; remove it so the retry does not leave a duplicate.
            modemMessages.removeAll { $0.isOutgoing && $0.index == index }
            if let client {
                Task { try? await client.delete(index: index) }
            }
        }
        send(message.text, number: conversation.number)
    }

    /// Strips spaces and punctuation from a phone number; sender names are passed through unchanged.
    private static func dialable(_ number: String) -> String {
        guard ContactsDirectory.key(for: number) != nil else { return number }
        return number.filter { $0 == "+" || ($0.isASCII && $0.isNumber) }
    }

    /// Permanently deletes every message of the conversation from the stick.
    func delete(_ id: Conversation.ID) {
        let indexes = modemMessages.filter { Conversation.id(for: $0.phone) == id }.compactMap(\.index)
        modemMessages.removeAll { Conversation.id(for: $0.phone) == id }
        pending.removeAll { Conversation.id(for: $0.number) == id }
        if let draftNumber, Conversation.id(for: draftNumber) == id { self.draftNumber = nil }
        rebuild()
        selectedIDs.remove(id)
        if selection == id { selection = selectedIDs.first ?? sortedConversations.first?.id }
        guard let client else { return }
        Task {
            for index in indexes { try? await client.delete(index: index) }
            lastCounts = nil
        }
    }
}

enum SampleData {
    static var messages: [ModemSMS] {
        let now = Date()
        let day = 1440.0
        func sms(_ phone: String, _ text: String, _ minutesAgo: Double, out: Bool = false, unread: Bool = false) -> ModemSMS {
            ModemSMS(index: nil, phone: phone, content: text, date: now.addingTimeInterval(-minutesAgo * 60),
                     isOutgoing: out, isUnread: unread, hasFailed: false)
        }
        let anna = "+48 601 234 567", parcel = "+48 512 908 771", tom = "+44 7700 900123"

        return [
            sms(anna, "Hey, are you still coming on Saturday?", day + 190),
            sms(anna, "Yes! What time should I be there?", day + 185, out: true),
            sms(anna, "Around 6", day + 183),
            sms(anna, "We're doing dinner first and then heading out", day + 182.9),
            sms(anna, "Perfect, I'll bring dessert", day + 180, out: true),
            sms(anna, "Did you get the tickets?", 42),
            sms(anna, "Just booked them", 40, out: true),
            sms(anna, "Row 7, right in the middle 🎉", 39.9, out: true),
            sms(anna, "Amazing, thank you!!", 12),
            sms("Carrier", "Your data package of 30 GB has been activated and is valid for 30 days.", 3 * day),
            sms("Carrier", "You have used 80% of your data allowance. Reply MORE to add 10 GB.", 95, unread: true),
            sms(parcel, "Hi, your parcel is at the pickup point. Code: 4471", day + 30),
            sms(parcel, "Thanks, I'll collect it today", day + 20, out: true),
            sms(tom, "Landed! Wifi here is terrible so texting this number instead", 2 * day + 60, out: true),
            sms(tom, "Ha, no worries. Call when you're at the hotel", 2 * day + 50),
            sms("BankAlert", "Your one-time code is 284 913. Never share this code with anyone.", 5 * day),
        ]
    }
}

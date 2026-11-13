import SwiftUI

struct SidebarView: View {
    @Environment(MessageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let conversations = store.filteredConversations
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                    let isSelected = store.selectedIDs.contains(conversation.id)
                    let nextSelected = index + 1 < conversations.count
                        && store.selectedIDs.contains(conversations[index + 1].id)
                    ConversationRow(
                        conversation: conversation,
                        isSelected: isSelected,
                        previousSelected: index > 0 && store.selectedIDs.contains(conversations[index - 1].id),
                        nextSelected: nextSelected
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // The click's own modifier keys, not whatever is held when the handler runs.
                        let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                        store.select(conversation.id, command: modifiers.contains(.command),
                                     shift: modifiers.contains(.shift))
                    }
                    .contextMenu {
                        let count = store.selectedIDs.contains(conversation.id) ? store.selectedIDs.count : 1
                        Button(count > 1 ? "Delete \(count) Conversations…" : "Delete Conversation…", role: .destructive) {
                            store.requestDelete(conversation.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
        }
        .overlay {
            if conversations.isEmpty {
                Text(store.showsUnreadOnly && store.searchText.isEmpty ? "No Unread Messages" : "No Results")
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { !store.pendingDeletion.isEmpty }, set: { if !$0 { store.pendingDeletion = [] } })
        ) {
            let ids = store.pendingDeletion
            Button(ids.count > 1 ? "Delete \(ids.count) Conversations" : "Delete", role: .destructive) {
                store.delete(ids)
            }
        } message: {
            Text(store.pendingDeletion.count > 1
                 ? "Their messages will be permanently deleted from the LTE stick."
                 : "Its messages will be permanently deleted from the LTE stick.")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchField(text: $store.searchText)
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ModemStatusBar(status: store.modem) { store.setOwnNumber($0) }
        }
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem {
                Menu {
                    Picker("Filter", selection: $store.showsUnreadOnly) {
                        Text("All Messages").tag(false)
                        Text("Unread").tag(true)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
                .menuIndicator(.hidden)
                .help("Filter conversations")
            }
        }
    }
}

extension SidebarView {
    private var deletionTitle: String {
        let ids = store.pendingDeletion
        if ids.count == 1, let title = store.conversation(ids.first)?.title {
            return "Delete the conversation with \(title)?"
        }
        return "Delete \(ids.count) conversations?"
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    /// Whether the rows directly above and below are selected too; neighbouring
    /// selected rows join into one highlighted block, as in Messages.
    let previousSelected: Bool
    let nextSelected: Bool
    @Environment(\.appearsActive) private var appearsActive

    /// Accent-coloured highlight; an inactive window shows a grey selection instead, as Messages does.
    private var isEmphasized: Bool { isSelected && appearsActive }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(conversation.hasUnread && !isEmphasized ? Color.blue : .clear)
                .frame(width: 8, height: 8)
                .frame(height: 40)

            AvatarView(conversation: conversation, size: 40)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conversation.lastMessage.map { DateText.sidebar($0.date) } ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(isEmphasized ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                }
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(isEmphasized ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.leading, 4)
        }
        .foregroundStyle(isEmphasized ? .white : .primary)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.top, 14)
        .frame(height: 80, alignment: .top)
        .background {
            if isSelected {
                UnevenRoundedRectangle(
                    topLeadingRadius: previousSelected ? 0 : 10,
                    bottomLeadingRadius: nextSelected ? 0 : 10,
                    bottomTrailingRadius: nextSelected ? 0 : 10,
                    topTrailingRadius: previousSelected ? 0 : 10,
                    style: .continuous
                )
                .fill(isEmphasized ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.1)))
            }
        }
        .overlay(alignment: .bottom) {
            if isSelected && nextSelected {
                // Divider inside a block of selected rows.
                Rectangle()
                    .fill(isEmphasized ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.separator))
                    .frame(height: 1)
                    .padding(.leading, 64)
                    .padding(.trailing, 10)
            } else if !isSelected && !nextSelected {
                Divider().padding(.leading, 64).padding(.trailing, 10)
            }
        }
    }

    private var preview: String {
        conversation.lastMessage?.text ?? "New Message"
    }
}

struct AvatarView: View {
    let initials: String?
    var imageData: Data?
    var size: CGFloat = 40

    init(name: String?, imageData: Data?, size: CGFloat = 40) {
        initials = name.flatMap(Conversation.initials(for:))
        self.imageData = imageData
        self.size = size
    }

    init(conversation: Conversation, size: CGFloat = 40) {
        initials = conversation.initials
        imageData = conversation.avatarData
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Theme.avatarTop, Theme.avatarBottom],
                    startPoint: .top, endPoint: .bottom
                )
            )
            if let imageData, let photo = NSImage(data: imageData) {
                Image(nsImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else if let initials {
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.62))
                    .offset(y: size * 0.1)
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct ModemStatusBar: View {
    let status: ModemStatus
    let onSetNumber: (String) -> Void
    @State private var didCopy = false
    @State private var isEditingNumber = false
    @State private var numberDraft = ""
    @State private var countryISO = "GB"

    var body: some View {
        // Two rows, so nothing is squeezed out when the sidebar is narrow:
        // network and storage on top, the SIM's own number below.
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                SignalBars(level: status.signalBars)
                Text(status.summary)
                Spacer(minLength: 8)
                if status.storageCapacity > 0 {
                    StorageIndicator(status: status)
                        .fixedSize()
                }
            }
            HStack(spacing: 6) {
                numberSection
                    .popover(isPresented: $isEditingNumber, arrowEdge: .top) { numberEditor }
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var numberSection: some View {
        if let number = status.phoneNumber {
            HStack(spacing: 6) {
                Text(number)
                    .help("This SIM's phone number")
                    .contextMenu {
                        if status.canEditNumber {
                            Button("Edit Number…") { beginEditing(number) }
                            Button("Remove Number") { onSetNumber("") }
                        }
                    }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(number, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied" : "Copy phone number")
                .accessibilityLabel("Copy phone number")

                if status.canEditNumber {
                    Button {
                        beginEditing(number)
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit phone number")
                    .accessibilityLabel("Edit phone number")
                }
            }
        } else {
            Button("Add your number") { beginEditing("") }
                .buttonStyle(.plain)
                .help("This SIM doesn't report its own number. Enter it once to show it here.")
        }
    }

    private var numberEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This SIM's phone number")
                .font(.headline)
            Text("The SIM doesn't report its own number, so enter it once. It is only shown here and saved on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Country", selection: $countryISO) {
                ForEach(Country.all) { country in
                    Text("\(country.flag) \(country.name) (+\(country.dialCode))").tag(country.iso)
                }
            }
            .labelsHidden()
            HStack(spacing: 6) {
                Text("+\(Country.with(iso: countryISO)?.dialCode ?? "")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                TextField("Phone number", text: $numberDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveNumber)
            }
            // Say what is wrong once something has been typed; an empty field just disables Save.
            if case .failure(let error) = validation, !numberDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if status.phoneNumber != nil {
                    Button("Remove", role: .destructive) {
                        onSetNumber("")
                        isEditingNumber = false
                    }
                }
                Spacer()
                Button("Cancel") { isEditingNumber = false }
                Button("Save", action: saveNumber)
                    .keyboardShortcut(.defaultAction)
                    .disabled(savableNumber == nil)
            }
        }
        .padding(14)
        .frame(width: 280)
        .lineLimit(nil)
        .foregroundStyle(.primary)
    }

    /// Opens the editor with the country prefilled: from the saved number, else from the SIM.
    private func beginEditing(_ current: String) {
        let fallback = status.simCountry ?? Country.with(iso: Locale.current.region?.identifier)
        if let parts = Country.split(number: current, preferred: fallback) {
            countryISO = parts.country.iso
            numberDraft = parts.national
        } else {
            countryISO = fallback?.iso ?? "GB"
            numberDraft = current
        }
        isEditingNumber = true
    }

    /// The typed number checked against the chosen country.
    private var validation: Result<String, Country.NumberError> {
        let typed = numberDraft.trimmingCharacters(in: .whitespaces)
        // A full international number pasted into the field carries its own country code.
        if typed.hasPrefix("+") {
            guard let parts = Country.split(number: typed, preferred: Country.with(iso: countryISO)) else {
                return .failure(.invalidCharacters)
            }
            return parts.country.normalized(national: parts.national)
        }
        guard let country = Country.with(iso: countryISO) else { return .failure(.empty) }
        return country.normalized(national: typed)
    }

    private var savableNumber: String? {
        if case .success(let number) = validation { return number }
        return nil
    }

    private func saveNumber() {
        guard let number = savableNumber else { return }
        onSetNumber(number)
        isEditingNumber = false
    }
}

/// How many messages are stored on the stick, with a warning once it is over 80% full.
struct StorageIndicator: View {
    let status: ModemStatus

    var body: some View {
        HStack(spacing: 3) {
            if status.isStorageNearlyFull {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(status.isStorageFull ? .red : .orange)
            }
            Text("\(status.storedMessages)/\(status.storageCapacity)")
                .monospacedDigit()
        }
        .help(explanation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(explanation)
    }

    private var explanation: String {
        let count = "\(status.storedMessages) of \(status.storageCapacity) messages stored on the stick."
        if status.isStorageFull { return count + " It is full: new messages cannot arrive until you delete some." }
        if status.isStorageNearlyFull { return count + " It is nearly full: delete old conversations, or new messages will stop arriving." }
        return count
    }
}

struct SignalBars: View {
    /// 0...5
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < level ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: 4 + CGFloat(index) * 1.8)
            }
        }
        .accessibilityLabel("Signal \(level) of 5")
    }
}

enum DateText {
    static func sidebar(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    static func threadHeader(_ date: Date) -> (day: String, time: String) {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return (day, date.formatted(date: .omitted, time: .shortened))
    }
}

import SwiftUI

struct ChatView: View {
    @Environment(MessageStore.self) private var store
    let conversation: Conversation
    @State private var draft = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        MessageRow(row: row) { store.retry(row.id, in: conversation.id) }
                    }
                    Color.clear.frame(height: 6).id(bottomID)
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: conversation.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(text: $draft) {
                store.send(draft, in: conversation.id)
                draft = ""
            }
        }
        .overlay(alignment: .top) {
            ThreadHeader(conversation: conversation)
                .padding(.top, 8)
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    private let bottomID = "bottom"

    /// Messages annotated with grouping info (timestamp headers, bubble tails, status line).
    private var rows: [MessageRowModel] {
        let messages = conversation.messages
        return messages.enumerated().map { index, message in
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let showsHeader = previous.map { message.date.timeIntervalSince($0.date) > 3600 } ?? true
            let nextStartsGroup = next.map {
                $0.isOutgoing != message.isOutgoing || $0.date.timeIntervalSince(message.date) > 60
            } ?? true
            return MessageRowModel(
                message: message,
                showsHeader: showsHeader,
                startsGroup: showsHeader || previous?.isOutgoing != message.isOutgoing,
                hasTail: nextStartsGroup,
                // The last outgoing message always says how it went; a failed one says so wherever it is.
                showsStatus: message.isOutgoing && (next == nil || message.status == .failed)
            )
        }
    }
}

/// Floating avatar and name pill centred over the top of the thread, as in Messages.
struct ThreadHeader: View {
    let conversation: Conversation

    var body: some View {
        VStack(spacing: 5) {
            AvatarView(conversation: conversation, size: 40)
                .zIndex(1)
            Text(conversation.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .glassEffect(.regular, in: .capsule)
        }
        .help(conversation.number)
    }
}

struct MessageRowModel: Identifiable {
    let message: Message
    let showsHeader: Bool
    let startsGroup: Bool
    let hasTail: Bool
    let showsStatus: Bool
    var id: Message.ID { message.id }
}

struct MessageRow: View {
    let row: MessageRowModel
    /// Sends a failed message again.
    var onRetry: () -> Void = {}

    var body: some View {
        let message = row.message
        VStack(spacing: 0) {
            if row.showsHeader {
                let header = DateText.threadHeader(message.date)
                Text("\(Text(header.day).fontWeight(.bold)) \(header.time)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 0) {
                if message.isOutgoing { Spacer(minLength: 100) }
                Text(MessageText.attributed(message.text))
                    .font(.system(size: 13))
                    .tint(message.isOutgoing ? .white : .blue)
                    .textSelection(.enabled)
                    .foregroundStyle(message.isOutgoing ? .white : .primary)
                    .padding(.vertical, 7)
                    .padding(.leading, message.isOutgoing ? 12 : 12 + BubbleShape.tailWidth)
                    .padding(.trailing, message.isOutgoing ? 12 + BubbleShape.tailWidth : 12)
                    .background(
                        BubbleShape(isOutgoing: message.isOutgoing, hasTail: row.hasTail)
                            .fill(message.isOutgoing ? Theme.outgoingBubble : Theme.incomingBubble)
                    )
                    .opacity(message.status == .sending ? 0.6 : 1)
                    .frame(maxWidth: 420, alignment: message.isOutgoing ? .trailing : .leading)
                if message.status == .failed {
                    Button(action: onRetry) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .help("Not delivered. Click to try again.")
                    .accessibilityLabel("Try sending again")
                }
                if !message.isOutgoing { Spacer(minLength: 100) }
            }
            .padding(.top, row.showsHeader ? 0 : (row.startsGroup ? 8 : 3))

            if row.showsStatus {
                HStack(spacing: 6) {
                    Text(statusText(message.status))
                        .foregroundStyle(message.status == .failed ? .red : .secondary)
                    if message.status == .failed {
                        Button("Try Again", action: onRetry)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, BubbleShape.tailWidth + 4)
                .padding(.top, 3)
            }
        }
        .animation(.easeOut(duration: 0.2), value: message.status)
    }

    private func statusText(_ status: Message.Status) -> String {
        switch status {
        case .sending: "Sending…"
        case .sent: "Sent"
        case .failed: "Not Delivered"
        }
    }
}

/// Rounded message bubble with an optional tail in the bottom corner.
struct BubbleShape: Shape {
    static let tailWidth: CGFloat = 5

    let isOutgoing: Bool
    let hasTail: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let body = CGRect(x: 0, y: 0, width: w - Self.tailWidth, height: h)
        var path = Path(roundedRect: body, cornerRadius: min(15, h / 2), style: .continuous)

        if hasTail {
            let x = body.maxX
            var tail = Path()
            tail.move(to: CGPoint(x: x - 1, y: h - 15))
            tail.addQuadCurve(to: CGPoint(x: x + Self.tailWidth, y: h), control: CGPoint(x: x, y: h - 3))
            tail.addQuadCurve(to: CGPoint(x: x - 10, y: h - 5), control: CGPoint(x: x - 3, y: h))
            tail.closeSubpath()
            path.addPath(tail)
        }

        if !isOutgoing {
            path = path.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
        }
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Capsule message field floating over the bottom of the thread, with an emoji button beside it.
struct ComposerView: View {
    @Binding var text: String
    var canSend = true
    /// Whether the field takes keyboard focus as soon as it appears.
    var autoFocus = true
    /// Change this value to move keyboard focus into the field.
    var focusRequest = 0
    let onSend: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                // The placeholder is drawn here rather than by the text field: the field's own
                // placeholder went missing after the window was closed to the menu bar and reopened.
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("Text Message • SMS")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TextField("", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...6)
                        .focused($isFocused)
                        .onSubmit(send)
                        .accessibilityLabel("Text Message")
                }
                .padding(.vertical, 7)

                if !trimmed.isEmpty {
                    let count = SMSCounter.count(text)
                    Text(count.segments > 1 ? "\(count.used)/\(count.capacity) · \(count.segments) SMS" : "\(count.used)/\(count.capacity)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSendable ? Theme.outgoingBubble : Color.gray.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSendable)
                    .padding(.bottom, 3)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Theme.fieldFill)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Button {
                isFocused = true
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Image(systemName: "face.smiling.inverse")
                    .font(.system(size: 15))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(true), in: .circle)
            .help("Emoji & Symbols")
        }
        .animation(.easeOut(duration: 0.15), value: trimmed.isEmpty)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                stops: [.init(color: Theme.threadBackground.opacity(0), location: 0),
                        .init(color: Theme.threadBackground, location: 0.45)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .task {
            // Wait a beat: when this view replaces New Message, the field that had focus
            // is still being removed, and an immediate request is dropped.
            guard autoFocus else { return }
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = true
        }
        .onChange(of: focusRequest) { isFocused = true }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSendable: Bool { canSend && !trimmed.isEmpty }

    private func send() {
        guard isSendable else { return }
        onSend()
    }
}

struct NewMessageView: View {
    @Environment(MessageStore.self) private var store
    @State private var recipient = ""
    @State private var draft = ""
    @State private var highlighted = 0
    @State private var composerFocusRequest = 0
    @FocusState private var recipientFocused: Bool

    var body: some View {
        let suggestions = store.recipientSuggestions(for: recipient)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("To:").foregroundStyle(.secondary)
                TextField("Name or phone number", text: $recipient)
                    .textFieldStyle(.plain)
                    .focused($recipientFocused)
                    .onSubmit { choose(from: suggestions) }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, max(suggestions.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { offset, entry in
                            SuggestionRow(entry: entry, isHighlighted: offset == highlighted)
                                .id(entry.id)
                                .contentShape(Rectangle())
                                .onTapGesture { store.openConversation(number: entry.number) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                }
                .onChange(of: highlighted) { _, new in
                    if suggestions.indices.contains(new) { proxy.scrollTo(suggestions[new].id) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(text: $draft, canSend: !recipient.trimmingCharacters(in: .whitespaces).isEmpty,
                         autoFocus: false, focusRequest: composerFocusRequest) {
                store.send(draft, to: recipient)
            }
        }
        .onChange(of: recipient) { highlighted = 0 }
        .defaultFocus($recipientFocused, true)
        .onAppear {
            Task { recipientFocused = true }
        }
    }

    /// Return in the "To:" field: open the highlighted suggestion, or the typed number if nothing matches.
    private func choose(from suggestions: [ContactEntry]) {
        let typed = recipient.trimmingCharacters(in: .whitespaces)
        if suggestions.indices.contains(highlighted) {
            store.openConversation(number: suggestions[highlighted].number)
        } else if ContactsDirectory.key(for: typed) != nil {
            store.openConversation(number: typed)
        } else if !typed.isEmpty {
            // Not a contact or a phone number (e.g. a sender name): keep it and move on to the message.
            composerFocusRequest += 1
        }
    }
}

struct SuggestionRow: View {
    let entry: ContactEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: entry.name == entry.number ? nil : entry.name, imageData: entry.imageData, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 13, weight: .medium))
                if entry.name != entry.number {
                    Text([entry.label, entry.number].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                }
            }
            Spacer()
        }
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
            }
        }
    }
}

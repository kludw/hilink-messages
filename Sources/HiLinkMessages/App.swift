import SwiftUI

@main
struct HiLinkMessagesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = MessageStore.shared

    var body: some Scene {
        Window("HiLink Messages", id: MainWindow.id) {
            RootView()
                .environment(store)
                .frame(minWidth: 720, minHeight: 460)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1024, height: 768)
        // Always show the window at launch, even if it was closed when the app last quit.
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    MainWindow.show()
                    store.startNewMessage()
                }
                .keyboardShortcut("n")
                .disabled(!store.modem.isUsable)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(store.selectedIDs.count > 1 ? "Delete Conversations…" : "Delete Conversation…") {
                    store.requestDeleteSelection()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selectedIDs.isEmpty || !store.modem.isUsable)
            }
        }

        // Closing the window leaves the app running here, so messages keep arriving.
        MenuBarExtra {
            MenuBarContent()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
    }
}

@MainActor
enum MainWindow {
    static let id = "main"
    /// Opens the main window; set by the window's root view the first time it appears.
    static var reopen: (() -> Void)?

    /// Brings the app back into the Dock and shows its window, reopening it if it was closed.
    static func show() {
        NSApp.setActivationPolicy(.regular)
        reopen?()
        NSApp.activate()
    }
}

/// The menu bar icon. It exists for as long as the app runs, window or not, so it is also what
/// keeps a way to open the main window available.
struct MenuBarLabel: View {
    @Environment(MessageStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = registerOpener()
        Image(nsImage: MenuBarIcon.image(
            level: store.modem.signalBars,
            isConnected: store.modem.isUsable,
            hasUnread: store.conversations.contains(where: \.hasUnread)
        ))
    }

    private func registerOpener() {
        if MainWindow.reopen == nil {
            let open = openWindow
            MainWindow.reopen = { open(id: MainWindow.id) }
        }
    }
}

struct MenuBarContent: View {
    @Environment(MessageStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let unread = store.conversations.filter(\.hasUnread).count
        Text(store.modem.summary)
        if unread > 0 {
            Text(unread == 1 ? "1 unread conversation" : "\(unread) unread conversations")
        }
        if store.modem.isStorageNearlyFull {
            Text(store.modem.isStorageFull
                 ? "Storage full: new messages cannot arrive"
                 : "Storage nearly full: \(store.modem.storedMessages) of \(store.modem.storageCapacity)")
        }
        Divider()
        Button("Open Messages") { open() }
        Button("New Message") {
            open()
            store.startNewMessage()
        }
        .disabled(!store.modem.isUsable)
        Divider()
        Button("Quit HiLink Messages") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open() {
        MainWindow.reopen = { openWindow(id: MainWindow.id) }
        MainWindow.show()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare binary (swift run) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Start talking to the stick whether or not a window is showing.
        MessageStore.shared.startIfNeeded()

        // The window normally opens by itself; if it has not shortly after launch, open it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { MainWindow.show() }
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: nil)
        center.addObserver(self, selector: #selector(windowDidBecomeMain), name: NSWindow.didBecomeMainNotification, object: nil)
    }

    /// Keep running in the menu bar when the window is closed; quit from the menu or with ⌘Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon or launching the app again reopens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindow.show() }
        return false
    }

    /// With the last window closed, leave the Dock and live only in the menu bar.
    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing.canBecomeMain else { return }
        let closingID = ObjectIdentifier(closing)
        Task { @MainActor in
            let hasWindow = NSApp.windows.contains {
                ObjectIdentifier($0) != closingID && $0.isVisible && $0.canBecomeMain
            }
            if !hasWindow { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// A window is back: return to the Dock.
    @objc private func windowDidBecomeMain(_ notification: Notification) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }
}

enum Theme {
    /// Outgoing bubble colour: the green Messages uses for SMS.
    static let outgoingBubble = Color(red: 0.36, green: 0.77, blue: 0.33)
    static let incomingBubble = dynamic(light: 0.91, dark: 0.23)
    static let threadBackground = dynamic(light: 1.0, dark: 0.12)
    static let fieldFill = dynamic(light: 0.95, dark: 0.19)

    /// Avatar gradient: lavender in light mode, deeper purple-grey in dark mode.
    static let avatarTop = dynamic(light: NSColor(red: 0.74, green: 0.75, blue: 0.90, alpha: 1),
                                   dark: NSColor(red: 0.60, green: 0.58, blue: 0.71, alpha: 1))
    static let avatarBottom = dynamic(light: NSColor(red: 0.55, green: 0.56, blue: 0.78, alpha: 1),
                                      dark: NSColor(red: 0.31, green: 0.29, blue: 0.42, alpha: 1))

    private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        dynamic(light: NSColor(white: light, alpha: 1), dark: NSColor(white: dark, alpha: 1))
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct RootView: View {
    @Environment(MessageStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.modem.isUsable {
                messages
            } else {
                // Nothing in the app works without the stick, so it takes over the whole window.
                ConnectionView(status: store.modem)
            }
        }
        .onAppear {
            MainWindow.reopen = { openWindow(id: MainWindow.id) }
        }
    }

    private var messages: some View {
        NavigationSplitView {
            SidebarView()
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            Group {
                if store.isComposingNew {
                    NewMessageView()
                } else if store.selectedIDs.count > 1 {
                    Text("\(store.selectedIDs.count) Conversations Selected")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let conversation = store.conversation(store.selection) {
                    ChatView(conversation: conversation)
                        .id(conversation.id)
                } else {
                    Text("No Conversation Selected")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.threadBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        store.startNewMessage()
                    } label: {
                        Label("New Message", systemImage: "square.and.pencil")
                    }
                    .help("New Message (⌘N)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if store.selectedIDs.count <= 1 { store.markRead(store.selection) }
        }
        .onChange(of: store.selection) { _, new in
            if new != nil { store.isComposingNew = false }
            if store.selectedIDs.count <= 1 { store.markRead(new) }
        }
    }
}

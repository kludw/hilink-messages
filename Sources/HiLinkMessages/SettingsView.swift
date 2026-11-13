import ServiceManagement
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            StickSettings()
                .tabItem { Label("Stick", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.Key.keepsRunningInMenuBar) private var keepsRunning = true
    @AppStorage(Preferences.Key.pollInterval) private var pollInterval = 5
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { launchesAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Keep running in the menu bar when the window is closed", isOn: $keepsRunning)
            } footer: {
                Text(keepsRunning
                     ? "Messages keep arriving with the window closed. Quit with ⌘Q."
                     : "Closing the window quits the app, and messages only arrive while it is open.")
            }

            Section {
                Picker("Check for new messages", selection: $pollInterval) {
                    ForEach(Preferences.pollIntervals, id: \.self) { seconds in
                        Text("Every \(seconds) seconds").tag(seconds)
                    }
                }
            } footer: {
                Text("Shorter intervals show new messages sooner and keep the stick busier.")
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Could not change the login setting: \(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct NotificationSettings: View {
    @AppStorage(Preferences.Key.playsSound) private var playsSound = true
    @AppStorage(Preferences.Key.tone) private var tone = Tone.note.rawValue
    @AppStorage(Preferences.Key.showsNotifications) private var showsNotifications = true

    var body: some View {
        Form {
            Section {
                Toggle("Play a sound when a message arrives", isOn: $playsSound)
                Picker("Sound", selection: $tone) {
                    ForEach(Tone.available) { tone in
                        Text(tone.name).tag(tone.rawValue)
                    }
                }
                .disabled(!playsSound)
                .onChange(of: tone) { _, new in
                    // Play the tone that was just picked, so it can be chosen by ear.
                    if let picked = Tone(rawValue: new) { Notifier.preview(picked) }
                }
            }

            Section {
                Toggle("Show notifications", isOn: $showsNotifications)
            } footer: {
                Text("Banners appear when HiLink Messages is not the active app. macOS must also allow them, under System Settings › Notifications.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Read-only facts about the connected stick.
private struct StickSettings: View {
    @Environment(MessageStore.self) private var store

    var body: some View {
        let modem = store.modem
        Form {
            Section {
                LabeledContent("Status", value: modem.summary)
                if modem.isConnected {
                    LabeledContent("Model", value: modem.deviceName.isEmpty ? "Unknown" : modem.deviceName)
                    LabeledContent("Firmware", value: modem.firmware.isEmpty ? "Unknown" : modem.firmware)
                    LabeledContent("Signal", value: "\(modem.signalBars) of 5 bars")
                    if modem.storageCapacity > 0 {
                        LabeledContent("Messages stored", value: "\(modem.storedMessages) of \(modem.storageCapacity)")
                    }
                    LabeledContent("Your number", value: modem.phoneNumber ?? "Not set")
                }
            } footer: {
                if modem.isConnected {
                    Text(modem.canEditNumber
                         ? "This SIM does not report its own number. Set or change it with the buttons at the bottom of the sidebar."
                         : "The number is reported by the SIM.")
                } else {
                    Text("Plug in the stick to see its details.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

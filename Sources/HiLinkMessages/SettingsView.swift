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
            MobileDataTab()
                .tabItem { Label("Mobile Data", systemImage: "arrow.up.arrow.down") }
            StickSettings()
                .tabItem { Label("Stick", systemImage: "mediastick") }
        }
        .frame(width: 520)
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
            }

            Section {
                Picker("Check for new messages", selection: $pollInterval) {
                    ForEach(Preferences.pollIntervals, id: \.self) { seconds in
                        Text("Every \(seconds) seconds").tag(seconds)
                    }
                }
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
            }
        }
        .formStyle(.grouped)
    }
}

/// Shown in place of a stick tab's contents while there is no stick to ask.
private struct StickUnavailable: View {
    var body: some View {
        Section {
            Text("Plug in the stick to see and change these settings.")
                .foregroundStyle(.secondary)
        }
    }
}

/// The last stick-settings error, if any.
private struct StickErrorRow: View {
    @Environment(MessageStore.self) private var store

    var body: some View {
        if let error = store.stickSettingsError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct MobileDataTab: View {
    @Environment(MessageStore.self) private var store
    @State private var isBusy = false

    var body: some View {
        Form {
            if !store.modem.isConnected {
                StickUnavailable()
            } else {
                if let settings = store.mobileData {
                    Section {
                        Toggle("Mobile data", isOn: Binding(get: { settings.isEnabled }, set: { enabled in
                            run { await store.setMobileData(enabled: enabled) }
                        }))
                        if let roaming = settings.allowsRoaming {
                            Toggle("Data roaming", isOn: Binding(get: { roaming }, set: { allowed in
                                run { await store.setRoaming(allowed: allowed) }
                            }))
                            .disabled(!settings.isEnabled)
                        }
                    }
                } else if store.stickSettingsError == nil {
                    Section { ProgressView().controlSize(.small) }
                }

                if let usage = store.dataUsage {
                    Section("This month") {
                        LabeledContent("Downloaded", value: bytes(usage.monthDownload))
                        LabeledContent("Uploaded", value: bytes(usage.monthUpload))
                        LabeledContent("Total", value: bytes(usage.monthDownload + usage.monthUpload))
                    }
                }
                StickErrorRow()
            }
        }
        .formStyle(.grouped)
        .disabled(isBusy)
        .task(id: store.modem.isConnected) {
            await store.loadMobileData()
            // Keep the usage figures fresh while the tab is open.
            while !Task.isCancelled {
                await store.loadDataUsage()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    private func run(_ action: @escaping () async -> Void) {
        isBusy = true
        Task {
            await action()
            isBusy = false
        }
    }
}

/// "2 hr, 14 min" style; under a minute shows seconds.
private func duration(_ seconds: Int64) -> String {
    let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.days, .hours, .minutes]
    return Duration.seconds(seconds).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: 2))
}

/// Facts about the connected stick, and a way to restart it.
private struct StickSettings: View {
    @Environment(MessageStore.self) private var store
    @State private var confirmsRestart = false
    @State private var confirmsReset = false

    var body: some View {
        let modem = store.modem
        Form {
            Section {
                LabeledContent("Status", value: modem.summary)
                if modem.isConnected {
                    LabeledContent("Signal", value: "\(modem.signalBars) of 5 bars")
                    if modem.storageCapacity > 0 {
                        LabeledContent("Messages stored", value: "\(modem.storedMessages) of \(modem.storageCapacity)")
                    }
                    LabeledContent("Your number", value: modem.phoneNumber ?? "Not set")
                }
            } footer: {
                if !modem.isConnected {
                    Text("Plug in the stick to see its details.")
                }
            }

            if modem.isConnected {
                Section("Device") {
                    let device = store.deviceDetails
                    LabeledContent("Model", value: text(device?.name ?? modem.deviceName))
                    LabeledContent("Firmware", value: text(device?.firmware ?? modem.firmware))
                    if let automatic = device?.updatesAutomatically {
                        Toggle("Update firmware automatically", isOn: Binding(get: { automatic }, set: { enabled in
                            Task { await store.setFirmwareAutoUpdate(enabled: enabled) }
                        }))
                    }
                    if let device {
                        LabeledContent("Hardware", value: text(device.hardware))
                        LabeledContent("Web interface", value: text(device.webUI))
                        LabeledContent("IMEI", value: text(device.imei))
                        LabeledContent("Serial number", value: text(device.serialNumber))
                        if let uptime = device.uptimeSeconds {
                            LabeledContent("Running for", value: duration(uptime))
                        }
                    }
                }
                .textSelection(.enabled)

                Section {
                    HStack {
                        Button("Restart Stick") { confirmsRestart = true }
                        Button("Reset Stick", role: .destructive) { confirmsReset = true }
                    }
                }
                StickErrorRow()
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restart the stick?", isPresented: $confirmsRestart) {
            Button("Restart") {
                Task { await store.restartStick() }
            }
        } message: {
            Text("Messages cannot be sent or received until it is back.")
        }
        .confirmationDialog("Reset the stick to its factory settings?", isPresented: $confirmsReset) {
            Button("Reset Stick", role: .destructive) {
                Task { await store.factoryResetStick() }
            }
        } message: {
            Text("Everything set up on the stick goes back to how it left the factory, and messages stored on it may be deleted. This cannot be undone.")
        }
        .task(id: modem.isConnected) { await store.loadDeviceDetails() }
    }

    private func text(_ value: String) -> String { value.isEmpty ? "Unknown" : value }
}

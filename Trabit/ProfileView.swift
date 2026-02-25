import SwiftUI
import SwiftData
import HealthKit

// MARK: - Profile & Settings Tab

struct ProfileView: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    // HealthKit enabled types stored as raw string set
    @AppStorage("hkEnabledTypes") private var hkEnabledTypesRaw = ""

    @State private var editingName = false
    @State private var tempName = ""
    @State private var showResetOnboarding = false
    @State private var isSyncingHealthKit = false
    @State private var hkSyncMessage: String?

    private var enabledTypeIDs: Set<String> {
        get { Set(hkEnabledTypesRaw.split(separator: ",").map(String.init)) }
    }

    private func toggleType(_ id: HKQuantityTypeIdentifier) {
        var current = enabledTypeIDs
        if current.contains(id.rawValue) {
            current.remove(id.rawValue)
        } else {
            current.insert(id.rawValue)
        }
        hkEnabledTypesRaw = current.joined(separator: ",")
    }

    private func isEnabled(_ id: HKQuantityTypeIdentifier) -> Bool {
        enabledTypeIDs.contains(id.rawValue)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Profile Header
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 60, height: 60)
                            Text(userName.isEmpty ? "?" : String(userName.prefix(1)).uppercased())
                                .font(.title).bold()
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if editingName {
                                TextField("Your name", text: $tempName)
                                    .font(.headline)
                                    .onSubmit {
                                        userName = tempName
                                        editingName = false
                                    }
                            } else {
                                Text(userName.isEmpty ? "Add your name" : userName)
                                    .font(.headline)
                                    .foregroundStyle(userName.isEmpty ? .secondary : .primary)
                            }
                            Text("Trabit Member")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(editingName ? "Done" : "Edit") {
                            if editingName {
                                userName = tempName
                            } else {
                                tempName = userName
                            }
                            editingName.toggle()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: HealthKit Integration
                Section {
                    if healthKitManager.isAvailable {
                        if healthKitManager.isAuthorized {
                            ForEach(HealthKitManager.supportedTypes, id: \.identifier) { typeInfo in
                                Toggle(isOn: Binding(
                                    get: { isEnabled(typeInfo.identifier) },
                                    set: { _ in toggleType(typeInfo.identifier) }
                                )) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(typeInfo.name).font(.subheadline)
                                            Text("in \(typeInfo.displayUnit)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: typeInfo.icon)
                                            .foregroundStyle(Color(hex: typeInfo.color))
                                    }
                                }
                            }

                            Button {
                                Task {
                                    isSyncingHealthKit = true
                                    let ids = Set(enabledTypeIDs.compactMap { HKQuantityTypeIdentifier(rawValue: $0) })
                                    await healthKitManager.syncToday(context: modelContext, enabledTypes: ids)
                                    isSyncingHealthKit = false
                                    hkSyncMessage = "Synced!"
                                    try? await Task.sleep(for: .seconds(2))
                                    hkSyncMessage = nil
                                }
                            } label: {
                                HStack {
                                    if isSyncingHealthKit {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(hkSyncMessage ?? "Sync Today's Data")
                                }
                            }
                            .disabled(isSyncingHealthKit || enabledTypeIDs.isEmpty)
                        } else {
                            Button {
                                Task { try? await healthKitManager.requestAuthorization() }
                            } label: {
                                Label("Connect Health App", systemImage: "heart.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    } else {
                        Label("Health not available on this device", systemImage: "heart.slash")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Label("Health Integration", systemImage: "heart.fill")
                } footer: {
                    Text("Enabled types sync automatically on app launch. Toggle to add data to your habits.")
                }

                // MARK: App Settings
                Section("App") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }

                    Button {
                        showResetOnboarding = true
                    } label: {
                        Label("Show Welcome Tour Again", systemImage: "questionmark.circle")
                    }
                }

                // MARK: About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://trabit.app")!) {
                        Label("Website", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://trabit.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }
            }
            .navigationTitle("Profile")
            .alert("Reset Tour?", isPresented: $showResetOnboarding) {
                Button("Reset", role: .destructive) { hasCompletedOnboarding = false }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will show the onboarding again on next launch.")
            }
        }
    }
}

// MARK: - Notification Settings

private struct NotificationSettingsView: View {
    @State private var authStatus: String = "Checking…"

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(authStatus).foregroundStyle(.secondary)
                }
                Button("Open System Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("Notification Permission")
            } footer: {
                Text("Per-habit reminders are configured in each habit's edit screen.")
            }
        }
        .navigationTitle("Notifications")
        .task {
            let center = await UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized: authStatus = "Allowed"
            case .denied: authStatus = "Denied — enable in Settings"
            case .notDetermined: authStatus = "Not yet asked"
            case .provisional: authStatus = "Provisional"
            case .ephemeral: authStatus = "Ephemeral"
            @unknown default: authStatus = "Unknown"
            }
        }
    }
}

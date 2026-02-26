import SwiftUI
import SwiftData
import HealthKit
import UserNotifications
import PhotosUI

// MARK: - Profile & Settings

struct ProfileView: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("hkEnabledTypes") private var hkEnabledTypesRaw = ""

    @Query private var profiles: [UserProfile]

    @State private var editingName = false
    @State private var tempName = ""
    @State private var showResetOnboarding = false
    @State private var isSyncingHealthKit = false
    @State private var hkSyncMessage: String?
    @State private var photosItem: PhotosPickerItem?
    @State private var socialManager = CloudKitSocialManager.shared

    private var profile: UserProfile? { profiles.first }

    private var displayName: String {
        profile?.displayName.isEmpty == false ? profile!.displayName : userName
    }

    private var enabledTypeIDs: Set<String> {
        Set(hkEnabledTypesRaw.split(separator: ",").map(String.init))
    }

    private func toggleType(_ id: HKQuantityTypeIdentifier) {
        var current = enabledTypeIDs
        if current.contains(id.rawValue) { current.remove(id.rawValue) }
        else { current.insert(id.rawValue) }
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
                        PhotosPicker(selection: $photosItem, matching: .images) {
                            avatarView
                        }
                        .buttonStyle(.plain)
                        .onChange(of: photosItem) { _, item in loadPhoto(item) }

                        VStack(alignment: .leading, spacing: 2) {
                            if editingName {
                                TextField("Your name", text: $tempName)
                                    .font(.headline)
                                    .onSubmit { saveName() }
                            } else {
                                Text(displayName.isEmpty ? "Tap to add name" : displayName)
                                    .font(.headline)
                                    .foregroundStyle(displayName.isEmpty ? .secondary : .primary)
                            }
                            if let code = profile?.shareCode {
                                Text(code)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                        }
                        Spacer()
                        Button(editingName ? "Done" : "Edit") {
                            if editingName { saveName() } else { tempName = displayName }
                            editingName.toggle()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Tap your avatar to change photo. Share your code with friends from the Friends tab.")
                        .font(.caption)
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
                    Text("Enabled types sync automatically on app launch.")
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
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
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
            .onAppear { ensureProfile() }
        }
    }

    // MARK: - Avatar View

    @ViewBuilder
    private var avatarView: some View {
        AvatarView(
            avatarData: profile?.avatarData,
            name: displayName,
            size: 64,
            color: .blue
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(Color.blue))
        }
    }

    // MARK: - Helpers

    private func saveName() {
        userName = tempName
        if let p = profile {
            p.displayName = tempName
            // Sync updated name to CloudKit
            Task {
                try? await socialManager.ensureProfile(
                    displayName: tempName,
                    shareCode: p.shareCode,
                    avatarData: p.avatarData
                )
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let compressed = uiImage.jpegData(compressionQuality: 0.6) {
                if let p = profile {
                    p.avatarData = compressed
                }
            }
        }
    }

    private func ensureProfile() {
        if profiles.isEmpty {
            let p = UserProfile(name: userName)
            modelContext.insert(p)
            try? modelContext.save()
        } else if let p = profiles.first, p.displayName.isEmpty && !userName.isEmpty {
            p.displayName = userName
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
            let center = UNUserNotificationCenter.current()
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

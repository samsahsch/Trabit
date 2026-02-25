import SwiftUI
import SwiftData
import HealthKit
import UserNotifications
import PhotosUI

// MARK: - Profile & Settings Tab

struct ProfileView: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    // HealthKit enabled types stored as raw string set
    @AppStorage("hkEnabledTypes") private var hkEnabledTypesRaw = ""

    @Query private var profiles: [UserProfile]
    @Query private var friends: [FriendConnection]

    @State private var editingName = false
    @State private var tempName = ""
    @State private var showResetOnboarding = false
    @State private var isSyncingHealthKit = false
    @State private var hkSyncMessage: String?

    // Photo picker
    @State private var photosItem: PhotosPickerItem?

    // Friends
    @State private var showAddFriend = false
    @State private var showShareSheet = false
    @State private var selectedFriend: FriendConnection?
    @State private var showFriendDetail = false

    private var profile: UserProfile? { profiles.first }

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
                        // Avatar
                        PhotosPicker(selection: $photosItem, matching: .images) {
                            avatarView
                        }
                        .buttonStyle(.plain)
                        .onChange(of: photosItem) { _, item in
                            loadPhoto(item)
                        }

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
                    Text("Tap your avatar to change photo. Share your code so friends can add you.")
                        .font(.caption)
                }

                // MARK: Friends
                Section {
                    ForEach(friends) { friend in
                        Button {
                            selectedFriend = friend
                            showFriendDetail = true
                        } label: {
                            FriendRow(friend: friend)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for i in indexSet { modelContext.delete(friends[i]) }
                    }

                    Button {
                        showAddFriend = true
                    } label: {
                        Label("Add Friend", systemImage: "person.badge.plus")
                    }

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share My Goals", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Label("Friends", systemImage: "person.2.fill")
                } footer: {
                    Text("Friends can see only the goals you choose to share. Tap \"Share My Goals\" to export your shareable snapshot.")
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
            .sheet(isPresented: $showAddFriend) {
                AddFriendView { name, code, jsonPacket in
                    let friend = FriendConnection(name: name, code: code)
                    if let packet = jsonPacket {
                        friend.sharedGoalsJSON = packet
                        if let parsed = FriendSharePacket.from(jsonString: packet) {
                            if let avatarB64 = parsed.avatarBase64,
                               let data = Data(base64Encoded: avatarB64) {
                                friend.avatarData = data
                            }
                        }
                    }
                    modelContext.insert(friend)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareGoalsView(profile: profile)
            }
            .sheet(isPresented: $showFriendDetail) {
                if let friend = selectedFriend {
                    FriendDetailView(friend: friend)
                }
            }
            .onAppear { ensureProfile() }
        }
    }

    // MARK: - Avatar View

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 64, height: 64)
            if let data = profile?.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else {
                Text(displayName.isEmpty ? "?" : String(displayName.prefix(1)).uppercased())
                    .font(.title).bold()
                    .foregroundStyle(.blue)
            }
            // Camera overlay hint
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                )
                .opacity(0.0001) // invisible tap target — PhotosPicker handles it
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        profile?.displayName ?? userName
    }

    private func saveName() {
        userName = tempName
        if let p = profile {
            p.displayName = tempName
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Compress to thumbnail
                if let uiImage = UIImage(data: data),
                   let compressed = uiImage.jpegData(compressionQuality: 0.6) {
                    if let p = profile {
                        p.avatarData = compressed
                    }
                }
            }
        }
    }

    private func ensureProfile() {
        if profiles.isEmpty {
            let p = UserProfile(name: userName)
            modelContext.insert(p)
        } else if let p = profiles.first, p.displayName.isEmpty && !userName.isEmpty {
            p.displayName = userName
        }
    }
}

// MARK: - Friend Row

private struct FriendRow: View {
    let friend: FriendConnection

    var goals: [SharedGoalSnapshot] {
        guard let data = friend.sharedGoalsJSON.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SharedGoalSnapshot].self, from: data)) ?? []
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle().fill(Color.purple.opacity(0.15)).frame(width: 44, height: 44)
                if let data = friend.avatarData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 44, height: 44).clipShape(Circle())
                } else {
                    Text(String(friend.friendName.prefix(1)).uppercased())
                        .font(.headline).foregroundStyle(.purple)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.friendName).font(.subheadline).bold()
                Text(goals.isEmpty ? "No shared goals yet" : "\(goals.count) shared goal\(goals.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Friend Sheet

private struct AddFriendView: View {
    var onAdd: (String, String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var friendName = ""
    @State private var friendCode = ""
    @State private var jsonPaste = ""
    @State private var showJSONField = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Friend's Details") {
                    TextField("Name", text: $friendName)
                    TextField("Share Code (e.g. TRABIT-ABC123)", text: $friendCode)
                        .textInputAutocapitalization(.characters)
                }

                Section {
                    Toggle("Paste their shared goals JSON", isOn: $showJSONField)
                    if showJSONField {
                        TextEditor(text: $jsonPaste)
                            .frame(minHeight: 80)
                            .font(.caption.monospaced())
                    }
                } header: {
                    Text("Import Goals (optional)")
                } footer: {
                    Text("Your friend can export their goals from their Profile → Share My Goals.")
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addFriend() }
                        .disabled(friendName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  friendCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addFriend() {
        let name = friendName.trimmingCharacters(in: .whitespaces)
        let code = friendCode.trimmingCharacters(in: .whitespaces).uppercased()
        let json = showJSONField ? jsonPaste.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        // Validate JSON if provided
        if let j = json, !j.isEmpty {
            if FriendSharePacket.from(jsonString: j) == nil {
                errorMessage = "Could not read the pasted JSON. Make sure you copied it completely."
                return
            }
        }

        onAdd(name, code, json?.isEmpty == false ? json : nil)
        dismiss()
    }
}

// MARK: - Share Goals Sheet

private struct ShareGoalsView: View {
    let profile: UserProfile?
    @Environment(\.modelContext) private var modelContext
    @Query private var habits: [Habit]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGoalIDs: Set<String> = []
    @State private var exportedJSON: String?
    @State private var showCopied = false

    var shareableGoals: [(habit: Habit, goal: GoalDefinition)] {
        habits.flatMap { h in h.goals.filter { !$0.isArchived }.map { (h, $0) } }
    }

    var body: some View {
        NavigationStack {
            List {
                if shareableGoals.isEmpty {
                    ContentUnavailableView("No Goals", systemImage: "trophy", description: Text("Add goals to your habits to share them with friends."))
                } else {
                    Section {
                        ForEach(shareableGoals, id: \.goal.id) { pair in
                            let idStr = pair.goal.persistentModelID.hashValue.description
                            HStack {
                                Image(systemName: pair.habit.iconSymbol)
                                    .foregroundStyle(Color(hex: pair.habit.hexColor))
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pair.goal.name ?? pair.habit.name).font(.subheadline)
                                    Text(pair.habit.name).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedGoalIDs.contains(idStr) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedGoalIDs.contains(idStr) ? .blue : .secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedGoalIDs.contains(idStr) { selectedGoalIDs.remove(idStr) }
                                else { selectedGoalIDs.insert(idStr) }
                            }
                        }
                    } header: {
                        Text("Select goals to share")
                    }

                    if let json = exportedJSON {
                        Section("Your Share Packet") {
                            Text(json)
                                .font(.caption.monospaced())
                                .lineLimit(6)
                                .foregroundStyle(.secondary)
                            Button {
                                UIPasteboard.general.string = json
                                showCopied = true
                            } label: {
                                Label(showCopied ? "Copied!" : "Copy to Clipboard", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                            }
                            ShareLink(item: json, subject: Text("My Trabit Goals"), message: Text("Here are my shared goals from Trabit!")) {
                                Label("Share via Messages / AirDrop", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share My Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { buildPacket() }
                        .disabled(selectedGoalIDs.isEmpty)
                }
            }
        }
    }

    private func buildPacket() {
        guard let profile else { return }

        let selected = shareableGoals.filter { pair in
            let idStr = pair.goal.persistentModelID.hashValue.description
            return selectedGoalIDs.contains(idStr)
        }

        let snapshots = selected.map { pair -> SharedGoalSnapshot in
            let goal = pair.goal
            let habit = pair.habit
            let idStr = goal.persistentModelID.hashValue.description
            // Rough progress calculation
            let progress: Double
            if goal.kind == .consistency {
                let score = habit.consistencyScore(for: goal)
                let target = goal.consistencyDifficulty?.targetOccurrences ?? 30
                progress = min(Double(score) / Double(target), 1.0)
            } else if let target = goal.targetValue, goal.kind == .targetValue, let metric = goal.metricName {
                let total = habit.logs.flatMap { $0.entries }.filter { $0.metricName == metric }.reduce(0) { $0 + $1.value }
                progress = min(total / target, 1.0)
            } else {
                progress = goal.isCompleted ? 1.0 : 0.0
            }

            // Streak: consecutive days with at least one log
            let streak = computeStreak(for: habit)

            return SharedGoalSnapshot(
                id: idStr,
                habitName: habit.name,
                habitIcon: habit.iconSymbol,
                habitColor: habit.hexColor,
                goalKind: goal.kind.rawValue,
                goalName: goal.name ?? habit.name,
                targetValue: goal.targetValue,
                targetDate: goal.targetDate,
                progressPercent: progress,
                streakDays: streak,
                isCompleted: goal.isCompleted
            )
        }

        let avatarB64 = profile.avatarData.map { $0.base64EncodedString() }
        let packet = FriendSharePacket(
            senderName: profile.displayName,
            senderCode: profile.shareCode,
            avatarBase64: avatarB64,
            sharedGoals: snapshots,
            exportedAt: Date()
        )
        exportedJSON = packet.jsonString()
    }

    private func computeStreak(for habit: Habit) -> Int {
        var streak = 0
        var date = Date()
        let cal = Calendar.current
        while habit.logs.contains(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            streak += 1
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }
}

// MARK: - Friend Detail View

private struct FriendDetailView: View {
    let friend: FriendConnection
    @Environment(\.dismiss) private var dismiss
    @State private var importJSON = ""
    @State private var showImport = false

    var goals: [SharedGoalSnapshot] {
        guard let data = friend.sharedGoalsJSON.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SharedGoalSnapshot].self, from: data)) ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                // Friend header
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.purple.opacity(0.15)).frame(width: 56, height: 56)
                            if let data = friend.avatarData, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 56, height: 56).clipShape(Circle())
                            } else {
                                Text(String(friend.friendName.prefix(1)).uppercased())
                                    .font(.title2).foregroundStyle(.purple)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(friend.friendName).font(.headline)
                            Text(friend.shareCode).font(.caption2).foregroundStyle(.secondary).monospaced()
                            Text("Added \(friend.addedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Shared goals
                if goals.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No shared goals",
                            systemImage: "trophy",
                            description: Text("Ask \(friend.friendName) to export their goals and paste the JSON below.")
                        )
                    }
                } else {
                    Section("\(friend.friendName)'s Goals") {
                        ForEach(goals) { goal in
                            SharedGoalRow(goal: goal)
                        }
                    }
                }

                // Update goals
                Section {
                    Button {
                        showImport = true
                    } label: {
                        Label("Update Shared Goals", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .navigationTitle(friend.friendName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportFriendGoalsView(friend: friend)
            }
        }
    }
}

// MARK: - Import Friend Goals

private struct ImportFriendGoalsView: View {
    let friend: FriendConnection
    @Environment(\.dismiss) private var dismiss

    @State private var jsonText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $jsonText)
                        .frame(minHeight: 120)
                        .font(.caption.monospaced())
                } header: {
                    Text("Paste \(friend.friendName)'s share packet JSON")
                } footer: {
                    Text("They can export it from Profile → Share My Goals in Trabit.")
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Update Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importGoals() }
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importGoals() {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let packet = FriendSharePacket.from(jsonString: trimmed) else {
            errorMessage = "Could not read the JSON. Make sure you copied it completely."
            return
        }
        // Re-encode just the goals array
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(packet.sharedGoals),
           let str = String(data: data, encoding: .utf8) {
            friend.sharedGoalsJSON = str
        }
        if let avatarB64 = packet.avatarBase64, let data = Data(base64Encoded: avatarB64) {
            friend.avatarData = data
        }
        dismiss()
    }
}

// MARK: - Shared Goal Row

private struct SharedGoalRow: View {
    let goal: SharedGoalSnapshot

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: goal.habitIcon)
                .foregroundStyle(Color(hex: goal.habitColor))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(goal.goalName).font(.subheadline)
                    if goal.isCompleted {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                    }
                }
                Text(goal.habitName).font(.caption).foregroundStyle(.secondary)
                if goal.streakDays > 0 {
                    Text("\(goal.streakDays) day streak").font(.caption2).foregroundStyle(.orange)
                }
            }

            Spacer()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: goal.progressPercent)
                    .stroke(Color(hex: goal.habitColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(goal.progressPercent * 100))%")
                    .font(.system(size: 8, weight: .bold))
            }
            .frame(width: 36, height: 36)
        }
        .padding(.vertical, 2)
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

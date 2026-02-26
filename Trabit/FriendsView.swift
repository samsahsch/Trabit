// FriendsView.swift — Social/Friends tab (Duolingo-style accountability)
// Friends are discovered via CloudKit share codes.
// Only voluntarily shared goal snapshots are ever published.

import SwiftUI
import SwiftData
import CloudKit

// MARK: - Friends Tab Root

struct FriendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var friends: [FriendConnection]
    @State private var socialManager = CloudKitSocialManager.shared
    @State private var showProfileSheet = false
    @State private var showAddFriend = false
    @State private var isRefreshing = false
    @State private var addFriendError: String?
    @State private var showAddFriendError = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Your profile card
                    profileCard
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if friends.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    } else {
                        friendsList
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            refresh()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendByCodeView { code in
                    addFriendByCode(code)
                }
            }
            .alert("Could Not Add Friend", isPresented: $showAddFriendError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(addFriendError ?? "Unknown error")
            }
            .task {
                await socialManager.initialise()
                ensureProfile()
                if !friends.isEmpty { refresh() }
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        Button {
            showProfileSheet = true
        } label: {
            HStack(spacing: 14) {
                AvatarView(
                    avatarData: profile?.avatarData,
                    name: profile?.displayName ?? "",
                    size: 56,
                    color: .blue
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.displayName.isEmpty == false ? profile!.displayName : "Set Your Name")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let code = profile?.shareCode {
                        Text(code)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(socialManager.isSignedIn ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(socialManager.isSignedIn ? "iCloud connected" : "Sign in to iCloud to sync")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Friends List

    private var friendsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Friends")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 10)

            VStack(spacing: 10) {
                ForEach(friends) { friend in
                    FriendCard(
                        friend: friend,
                        liveGoals: socialManager.friendGoals[friend.friendRecordID] ?? friend.cachedGoals
                    )
                    .padding(.horizontal)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(friend)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }

            // Add friend button
            Button {
                showAddFriend = true
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(.blue)
                    Text("Add Friend by Code")
                        .foregroundStyle(.blue)
                    Spacer()
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 10)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.opacity(0.4))
            Text("No Friends Yet")
                .font(.title3).bold()
            Text("Add friends by their Trabit code and see each other's shared goal progress in real time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddFriend = true
            } label: {
                Label("Add a Friend", systemImage: "person.badge.plus")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func refresh() {
        isRefreshing = true
        Task {
            let friendLinks = friends.map {
                FriendLink(friendRecordID: $0.friendRecordID, friendName: $0.friendName, friendCode: $0.shareCode)
            }
            await socialManager.refreshAllFriendGoals(friends: friendLinks)
            // Update cached JSON in SwiftData
            for friend in friends {
                if let goals = socialManager.friendGoals[friend.friendRecordID] {
                    friend.updateGoals(goals)
                }
            }
            try? modelContext.save()
            isRefreshing = false
        }
    }

    private func addFriendByCode(_ code: String) {
        Task {
            do {
                let link = try await socialManager.addFriend(byCode: code)
                let conn = FriendConnection(name: link.friendName, code: link.friendCode, recordID: link.friendRecordID)
                conn.avatarData = link.avatarData
                modelContext.insert(conn)
                try? modelContext.save()
                // Immediately fetch their goals
                let goals = (try? await socialManager.fetchGoals(forFriendRecordID: link.friendRecordID)) ?? []
                conn.updateGoals(goals)
                socialManager.friendGoals[link.friendRecordID] = goals
                try? modelContext.save()
            } catch SocialError.friendNotFound {
                addFriendError = "No Trabit user found with code \"\(code)\". Check the code and try again."
                showAddFriendError = true
            } catch SocialError.notSignedIn {
                addFriendError = "Sign into iCloud in Settings to use the Friends feature."
                showAddFriendError = true
            } catch {
                addFriendError = error.localizedDescription
                showAddFriendError = true
            }
        }
    }

    private func ensureProfile() {
        if profiles.isEmpty {
            let p = UserProfile(name: "")
            modelContext.insert(p)
            try? modelContext.save()
        }
        // Push profile to CloudKit if signed in
        if socialManager.isSignedIn, let p = profiles.first {
            Task {
                try? await socialManager.ensureProfile(
                    displayName: p.displayName,
                    shareCode: p.shareCode,
                    avatarData: p.avatarData
                )
                p.cloudRecordID = socialManager.myRecordID
                try? modelContext.save()
            }
        }
    }
}

// MARK: - Friend Card

private struct FriendCard: View {
    let friend: FriendConnection
    let liveGoals: [SharedGoalRecord]
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    AvatarView(
                        avatarData: friend.avatarData,
                        name: friend.friendName,
                        size: 44,
                        color: .purple
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.friendName)
                            .font(.subheadline).bold()
                            .foregroundStyle(.primary)
                        Group {
                            if liveGoals.isEmpty {
                                Text("No shared goals yet")
                            } else {
                                let done = liveGoals.filter { $0.isCompleted || $0.progressPercent >= 1 }.count
                                Text("\(done) / \(liveGoals.count) goals complete")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Mini progress rings
                    if !liveGoals.isEmpty {
                        HStack(spacing: -6) {
                            ForEach(liveGoals.prefix(3)) { goal in
                                MiniProgressRing(
                                    progress: goal.progressPercent,
                                    color: Color(hex: goal.habitColor),
                                    icon: goal.habitIcon
                                )
                            }
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Expanded goals
            if isExpanded {
                Divider().padding(.horizontal)
                if liveGoals.isEmpty {
                    HStack {
                        Text("Ask \(friend.friendName) to share a goal from their Goals tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(liveGoals) { goal in
                            FriendGoalRow(goal: goal)
                            if goal.id != liveGoals.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Friend Goal Row

private struct FriendGoalRow: View {
    let goal: SharedGoalRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: goal.habitIcon)
                .foregroundStyle(Color(hex: goal.habitColor))
                .frame(width: 24)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(goal.goalName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if goal.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 8) {
                    Text(goal.habitName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if goal.streakDays > 0 {
                        Label("\(goal.streakDays)d streak", systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Progress arc
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(goal.progressPercent, 1))
                    .stroke(
                        Color(hex: goal.habitColor),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(min(goal.progressPercent, 1) * 100))%")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 40, height: 40)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Mini Progress Ring

private struct MiniProgressRing: View {
    let progress: Double
    let color: Color
    let icon: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 26, height: 26)
        .background(
            Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Reusable Avatar View

struct AvatarView: View {
    let avatarData: Data?
    let name: String
    let size: CGFloat
    let color: Color

    var initials: String {
        guard !name.isEmpty else { return "?" }
        return String(name.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
            if let data = avatarData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Add Friend By Code Sheet

private struct AddFriendByCodeView: View {
    var onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    var isValidCode: Bool { trimmedCode.hasPrefix("TRABIT-") && trimmedCode.count >= 13 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("TRABIT-XXXXXX", text: $code)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                } header: {
                    Text("Friend's Trabit Code")
                } footer: {
                    Text("Ask your friend to open their Friends tab and share their code with you.")
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(trimmedCode)
                        dismiss()
                    }
                    .disabled(!isValidCode)
                }
            }
        }
    }
}

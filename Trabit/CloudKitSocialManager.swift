// CloudKitSocialManager.swift — Handles all CloudKit operations for the social/friends feature.
// Uses CloudKit public database so friends can discover each other by share code.
// Private data (your own habits/logs) stays in SwiftData and never goes to CloudKit.
// Only voluntarily shared goal snapshots are published.

import Foundation
import CloudKit
import SwiftData
import SwiftUI

// MARK: - Shared Goal Record (CloudKit representation)

struct SharedGoalRecord: Identifiable, Codable {
    var id: String              // CKRecord.ID.recordName
    var ownerRecordID: String   // CKRecord.ID of the owner's profile
    var ownerName: String
    var ownerCode: String
    var habitName: String
    var habitIcon: String
    var habitColor: String
    var goalKind: String        // GoalKind.rawValue
    var goalName: String
    var targetValue: Double?
    var targetDate: Date?
    var progressValue: Double   // current accumulated value
    var progressPercent: Double // 0–1
    var streakDays: Int
    var isCompleted: Bool
    var updatedAt: Date
}

// MARK: - CloudKit Social Manager

@MainActor
@Observable
final class CloudKitSocialManager {
    static let shared = CloudKitSocialManager()

    // MARK: State
    var isSignedIn: Bool = false
    var myRecordID: String = ""
    var friendGoals: [String: [SharedGoalRecord]] = [:] // keyed by ownerRecordID
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: CloudKit config
    private let container = CKContainer(identifier: "iCloud.com.samsahsch.Trabit")
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    // Record types
    static let profileRecordType = "TrabitProfile"
    static let sharedGoalRecordType = "TrabitSharedGoal"
    static let friendLinkRecordType = "TrabitFriendLink"

    // MARK: - Initialise

    func initialise() async {
        do {
            let status = try await container.accountStatus()
            isSignedIn = (status == .available)
            if isSignedIn {
                let recordID = try await container.userRecordID()
                myRecordID = recordID.recordName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile Management

    /// Ensure a public profile record exists for this user. Returns the share code.
    func ensureProfile(displayName: String, shareCode: String, avatarData: Data?) async throws -> String {
        // Try to fetch existing
        let predicate = NSPredicate(format: "ownerRecordID == %@", myRecordID)
        let query = CKQuery(recordType: Self.profileRecordType, predicate: predicate)
        let result = try await publicDB.records(matching: query, resultsLimit: 1)
        let existing = result.matchResults.compactMap { try? $0.1.get() }.first

        let record = existing ?? CKRecord(recordType: Self.profileRecordType)
        record["ownerRecordID"] = myRecordID
        record["displayName"] = displayName
        record["shareCode"] = shareCode
        if let data = avatarData {
            // Store avatar as CKAsset
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("avatar.jpg")
            try data.write(to: tmpURL)
            record["avatar"] = CKAsset(fileURL: tmpURL)
        }
        record["updatedAt"] = Date()

        try await publicDB.save(record)
        return shareCode
    }

    // MARK: - Add Friend by Code

    func addFriend(byCode code: String) async throws -> FriendLink {
        let predicate = NSPredicate(format: "shareCode == %@", code.uppercased())
        let query = CKQuery(recordType: Self.profileRecordType, predicate: predicate)
        let result = try await publicDB.records(matching: query, resultsLimit: 1)

        guard let profileRecord = result.matchResults.compactMap({ try? $0.1.get() }).first else {
            throw SocialError.friendNotFound
        }

        let friendRecordID = profileRecord["ownerRecordID"] as? String ?? profileRecord.recordID.recordName
        let friendName = profileRecord["displayName"] as? String ?? "Trabit User"
        let friendCode = profileRecord["shareCode"] as? String ?? code

        // Fetch avatar if present
        var avatarData: Data?
        if let asset = profileRecord["avatar"] as? CKAsset, let fileURL = asset.fileURL {
            avatarData = try? Data(contentsOf: fileURL)
        }

        // Save friend link to private DB
        let linkRecord = CKRecord(recordType: Self.friendLinkRecordType)
        linkRecord["myRecordID"] = myRecordID
        linkRecord["friendRecordID"] = friendRecordID
        linkRecord["friendName"] = friendName
        linkRecord["friendCode"] = friendCode
        try await privateDB.save(linkRecord)

        return FriendLink(
            friendRecordID: friendRecordID,
            friendName: friendName,
            friendCode: friendCode,
            avatarData: avatarData
        )
    }

    // MARK: - Publish / Unpublish Shared Goal

    func publishSharedGoal(goal: GoalDefinition, habit: Habit, progressValue: Double, progressPercent: Double, streakDays: Int) async throws {
        let recordName = "goal-\(myRecordID)-\(goal.persistentModelID.hashValue)"
        let recordID = CKRecord.ID(recordName: recordName)

        var record: CKRecord
        do {
            record = try await publicDB.record(for: recordID)
        } catch {
            record = CKRecord(recordType: Self.sharedGoalRecordType, recordID: recordID)
        }

        record["ownerRecordID"] = myRecordID
        record["habitName"] = habit.name
        record["habitIcon"] = habit.iconSymbol
        record["habitColor"] = habit.hexColor
        record["goalKind"] = goal.kind.rawValue
        record["goalName"] = goal.name ?? habit.name
        record["targetValue"] = goal.targetValue
        record["targetDate"] = goal.targetDate
        record["progressValue"] = progressValue
        record["progressPercent"] = progressPercent
        record["streakDays"] = streakDays
        record["isCompleted"] = goal.isCompleted ? 1 : 0
        record["updatedAt"] = Date()

        try await publicDB.save(record)
    }

    func unpublishSharedGoal(goal: GoalDefinition, habit: Habit) async throws {
        let recordName = "goal-\(myRecordID)-\(goal.persistentModelID.hashValue)"
        let recordID = CKRecord.ID(recordName: recordName)
        try await publicDB.deleteRecord(withID: recordID)
    }

    // MARK: - Fetch Friend Goals

    func fetchGoals(forFriendRecordID friendID: String) async throws -> [SharedGoalRecord] {
        let predicate = NSPredicate(format: "ownerRecordID == %@", friendID)
        let query = CKQuery(recordType: Self.sharedGoalRecordType, predicate: predicate)
        let result = try await publicDB.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }

        return records.compactMap { record -> SharedGoalRecord? in
            guard let ownerID = record["ownerRecordID"] as? String,
                  let habitName = record["habitName"] as? String,
                  let goalKind = record["goalKind"] as? String else { return nil }
            return SharedGoalRecord(
                id: record.recordID.recordName,
                ownerRecordID: ownerID,
                ownerName: "",
                ownerCode: "",
                habitName: habitName,
                habitIcon: record["habitIcon"] as? String ?? "star.fill",
                habitColor: record["habitColor"] as? String ?? "007AFF",
                goalKind: goalKind,
                goalName: record["goalName"] as? String ?? habitName,
                targetValue: record["targetValue"] as? Double,
                targetDate: record["targetDate"] as? Date,
                progressValue: record["progressValue"] as? Double ?? 0,
                progressPercent: record["progressPercent"] as? Double ?? 0,
                streakDays: record["streakDays"] as? Int ?? 0,
                isCompleted: (record["isCompleted"] as? Int ?? 0) == 1,
                updatedAt: record["updatedAt"] as? Date ?? Date()
            )
        }
    }

    /// Refresh all friends' goals and cache them
    func refreshAllFriendGoals(friends: [FriendLink]) async {
        isLoading = true
        defer { isLoading = false }
        for friend in friends {
            do {
                let goals = try await fetchGoals(forFriendRecordID: friend.friendRecordID)
                friendGoals[friend.friendRecordID] = goals
            } catch {
                // Silently skip failed fetches
            }
        }
    }

    // MARK: - Subscribe to Friend Updates (push notifications)

    func subscribeFriendUpdates(friendRecordIDs: [String]) async {
        // One subscription per friend — CloudKit will push a silent notification
        for friendID in friendRecordIDs {
            let subID = "friend-goals-\(friendID)"
            // Check if already subscribed
            if (try? await publicDB.subscription(for: CKSubscription.ID(subID))) != nil { continue }

            let predicate = NSPredicate(format: "ownerRecordID == %@", friendID)
            let sub = CKQuerySubscription(
                recordType: Self.sharedGoalRecordType,
                predicate: predicate,
                subscriptionID: subID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate]
            )
            let notif = CKSubscription.NotificationInfo()
            notif.shouldSendContentAvailable = true   // silent push
            notif.alertBody = "A friend updated their goal in Trabit!"
            sub.notificationInfo = notif
            try? await publicDB.save(sub)
        }
    }
}

// MARK: - Errors

enum SocialError: LocalizedError {
    case friendNotFound
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .friendNotFound: return "No Trabit user found with that code. Check the code and try again."
        case .notSignedIn: return "You need to be signed into iCloud to use the Friends feature."
        }
    }
}

// MARK: - FriendLink Model (local SwiftData, replaces old FriendConnection)

// NOTE: FriendModels.swift still contains UserProfile and FriendConnection for backwards compat.
// FriendLink is a lightweight in-memory struct used by the social manager.
struct FriendLink: Identifiable {
    let id = UUID()
    var friendRecordID: String
    var friendName: String
    var friendCode: String
    var avatarData: Data?
    var addedAt: Date = Date()
}

// FriendModels.swift — SwiftData models for the social/friends feature.
// Actual real-time data exchange uses CloudKit (CloudKitSocialManager.swift).
// These local models cache friend data so the app works offline.

import Foundation
import SwiftData
import SwiftUI

// MARK: - User Profile (local + synced to CloudKit public DB)

@Model final class UserProfile {
    var displayName: String
    var avatarData: Data?
    /// Readable invite code shown to friends, e.g. "TRABIT-A1B2C3"
    var shareCode: String
    /// CloudKit record name for this user (iCloud record ID)
    var cloudRecordID: String
    var joinedAt: Date

    init(name: String, cloudRecordID: String = "") {
        self.displayName = name
        self.shareCode = UserProfile.generateCode()
        self.cloudRecordID = cloudRecordID
        self.joinedAt = Date()
    }

    static func generateCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let code = (0..<6).map { _ in String(chars.randomElement()!) }.joined()
        return "TRABIT-\(code)"
    }
}

// MARK: - Friend Connection (cached locally, source of truth is CloudKit)

@Model final class FriendConnection {
    var friendName: String
    var shareCode: String
    var friendRecordID: String      // CloudKit record ID
    var avatarData: Data?
    var addedAt: Date
    /// Cached JSON array of SharedGoalRecord (refreshed from CloudKit)
    var cachedGoalsJSON: String
    var lastRefreshed: Date?

    init(name: String, code: String, recordID: String = "") {
        self.friendName = name
        self.shareCode = code
        self.friendRecordID = recordID
        self.addedAt = Date()
        self.cachedGoalsJSON = "[]"
    }

    var cachedGoals: [SharedGoalRecord] {
        guard let data = cachedGoalsJSON.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SharedGoalRecord].self, from: data)) ?? []
    }

    func updateGoals(_ goals: [SharedGoalRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(goals),
           let str = String(data: data, encoding: .utf8) {
            cachedGoalsJSON = str
            lastRefreshed = Date()
        }
    }
}

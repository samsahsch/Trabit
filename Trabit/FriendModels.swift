// FriendModels.swift — Local friend connection model for shared goals.
// Friends are identified by a unique user code. Each user can share goals
// they explicitly opt-in to sharing. Data is stored locally; sharing is
// done via exported JSON that a friend imports.

import Foundation
import SwiftData

// MARK: - User Profile

/// Persisted user profile. One instance per device.
@Model final class UserProfile {
    var displayName: String
    /// Base64-encoded JPEG thumbnail for the avatar (optional)
    var avatarData: Data?
    /// Unique code others use to add this person as a friend (e.g. "TRABIT-A1B2C3")
    var shareCode: String
    var createdAt: Date

    init(name: String) {
        self.displayName = name
        self.shareCode = UserProfile.generateCode()
        self.createdAt = Date()
    }

    static func generateCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let code = (0..<6).map { _ in String(chars.randomElement()!) }.joined()
        return "TRABIT-\(code)"
    }
}

// MARK: - Friend Connection

/// Represents a friend whose goals we can view. Stored locally.
@Model final class FriendConnection {
    var friendName: String
    var shareCode: String
    var avatarData: Data?
    var addedAt: Date
    /// JSON blob of the friend's shared goals snapshot (updated when they share)
    var sharedGoalsJSON: String

    init(name: String, code: String) {
        self.friendName = name
        self.shareCode = code
        self.addedAt = Date()
        self.sharedGoalsJSON = "[]"
    }
}

// MARK: - Shared Goal Snapshot (Codable for JSON transfer)

struct SharedGoalSnapshot: Codable, Identifiable {
    var id: String          // goal UUID string
    var habitName: String
    var habitIcon: String
    var habitColor: String
    var goalKind: String    // "targetValue" | "deadline" | "consistency"
    var goalName: String
    var targetValue: Double?
    var targetDate: Date?
    var progressPercent: Double // 0.0–1.0, computed at export time
    var streakDays: Int
    var isCompleted: Bool
}

// MARK: - Share Packet (exported / imported)

struct FriendSharePacket: Codable {
    var senderName: String
    var senderCode: String
    var avatarBase64: String?   // base64-encoded JPEG or nil
    var sharedGoals: [SharedGoalSnapshot]
    var exportedAt: Date

    /// Encode to a JSON string suitable for sharing
    func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode from a pasted / imported JSON string
    static func from(jsonString: String) -> FriendSharePacket? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FriendSharePacket.self, from: data)
    }
}

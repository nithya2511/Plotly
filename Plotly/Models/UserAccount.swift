import Foundation
import SwiftData

@Model
final class UserAccount {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var email: String
    var createdAt: Date
    var lastSignedInAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String,
        createdAt: Date = Date(),
        lastSignedInAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.createdAt = createdAt
        self.lastSignedInAt = lastSignedInAt
    }
}

struct UserAccountSnapshot: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let email: String

    static let guestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let guest = UserAccountSnapshot(
        id: guestID,
        displayName: "Guest",
        email: "Local trips only"
    )

    var isGuest: Bool {
        id == Self.guestID
    }
}

extension UserAccount {
    var snapshot: UserAccountSnapshot {
        UserAccountSnapshot(
            id: id,
            displayName: displayName,
            email: email
        )
    }
}

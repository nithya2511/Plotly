import Foundation
import SwiftData

@Model
final class Plan {
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var title: String
    var isCurrent: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        title: String,
        isCurrent: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.title = title
        self.isCurrent = isCurrent
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PlanStop {
    @Attribute(.unique) var id: UUID
    var planID: UUID
    var placeID: String
    var name: String
    var formattedAddress: String
    var latitude: Double
    var longitude: Double
    var note: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        planID: UUID,
        placeID: String,
        name: String,
        formattedAddress: String,
        latitude: Double,
        longitude: Double,
        note: String = "",
        sortIndex: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.planID = planID
        self.placeID = placeID
        self.name = name
        self.formattedAddress = formattedAddress
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PlanStop {
    var snapshot: PlanStopSnapshot {
        PlanStopSnapshot(
            id: id,
            placeID: placeID,
            name: name,
            formattedAddress: formattedAddress,
            latitude: latitude,
            longitude: longitude,
            note: note,
            sortIndex: sortIndex
        )
    }
}

import CoreLocation
import Foundation

struct PlaceSuggestion: Identifiable, Equatable {
    let id: String
    let placeID: String
    let primaryText: String
    let secondaryText: String

    init(placeID: String, primaryText: String, secondaryText: String) {
        self.id = placeID
        self.placeID = placeID
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}

struct PlaceDetails: Equatable {
    let placeID: String
    let name: String
    let formattedAddress: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PlanSnapshot: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isFavorite: Bool
    let stops: [PlanStopSnapshot]
}

struct PlanStopSnapshot: Identifiable, Equatable {
    let id: UUID
    let placeID: String
    let name: String
    let formattedAddress: String
    let latitude: Double
    let longitude: Double
    let note: String
    let sortIndex: Int
    let isCompleted: Bool

    init(
        id: UUID,
        placeID: String,
        name: String,
        formattedAddress: String,
        latitude: Double,
        longitude: Double,
        note: String,
        sortIndex: Int,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.placeID = placeID
        self.name = name
        self.formattedAddress = formattedAddress
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
        self.sortIndex = sortIndex
        self.isCompleted = isCompleted
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

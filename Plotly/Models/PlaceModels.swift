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

struct PlanSnapshot: Equatable {
    let id: UUID
    let title: String
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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

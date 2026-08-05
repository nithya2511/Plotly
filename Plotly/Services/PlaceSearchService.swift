import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
protocol PlaceSearchService {
    func suggestions(for query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceSuggestion]
    func details(for suggestion: PlaceSuggestion) async throws -> PlaceDetails
    func details(for mapFeature: MapFeature) async throws -> PlaceDetails
}

enum PlaceSearchServiceFactory {
    @MainActor
    static func live() -> PlaceSearchService {
        MapKitPlaceSearchService()
    }
}

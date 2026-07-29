import CoreLocation
import Foundation

@MainActor
protocol PlaceSearchService {
    func suggestions(for query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceSuggestion]
    func details(for suggestion: PlaceSuggestion) async throws -> PlaceDetails
}

enum PlaceSearchServiceFactory {
    @MainActor
    static func live() -> PlaceSearchService {
        #if canImport(GooglePlaces)
        if GoogleSDKBootstrap.configureIfPossible() {
            return GooglePlacesSearchService()
        }
        #endif

        return MapKitPlaceSearchService()
    }
}

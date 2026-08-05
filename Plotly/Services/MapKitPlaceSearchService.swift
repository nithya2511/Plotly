import CoreLocation
import MapKit
import SwiftUI

@MainActor
final class MapKitPlaceSearchService: NSObject, PlaceSearchService, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var suggestionContinuation: CheckedContinuation<[PlaceSuggestion], Error>?
    private var completionsByID: [String: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func suggestions(for query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return []
        }

        if let coordinate {
            let span = MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
            completer.region = MKCoordinateRegion(center: coordinate, span: span)
        }

        return try await withCheckedThrowingContinuation { continuation in
            suggestionContinuation?.resume(returning: [])
            suggestionContinuation = continuation
            completer.queryFragment = trimmed
        }
    }

    func details(for suggestion: PlaceSuggestion) async throws -> PlaceDetails {
        guard let completion = completionsByID[suggestion.placeID] else {
            throw PlaceSearchError.missingCompletion
        }

        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw PlaceSearchError.noDetails
        }

        let placemark = item.placemark
        return PlaceDetails(
            placeID: suggestion.placeID,
            name: item.name ?? suggestion.primaryText,
            formattedAddress: [placemark.title, placemark.locality, placemark.country]
                .compactMap { $0 }
                .removingDuplicates()
                .joined(separator: ", "),
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
    }

    func details(for mapFeature: MapFeature) async throws -> PlaceDetails {
        let request = MKMapItemRequest(feature: mapFeature)
        let item = try await request.mapItem
        return placeDetails(
            for: item,
            fallbackName: mapFeature.title ?? "Selected Place",
            fallbackPlaceID: mapFeaturePlaceID(for: mapFeature)
        )
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            let suggestions = completer.results.map { completion in
                let id = [completion.title, completion.subtitle].joined(separator: "|")
                completionsByID[id] = completion
                return PlaceSuggestion(
                    placeID: id,
                    primaryText: completion.title,
                    secondaryText: completion.subtitle
                )
            }
            suggestionContinuation?.resume(returning: suggestions)
            suggestionContinuation = nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            suggestionContinuation?.resume(throwing: error)
            suggestionContinuation = nil
        }
    }
}

enum PlaceSearchError: LocalizedError {
    case missingCompletion
    case noDetails

    var errorDescription: String? {
        switch self {
        case .missingCompletion:
            return "The selected place is no longer available."
        case .noDetails:
            return "No location details were found for that place."
        }
    }
}

private extension MapKitPlaceSearchService {
    func placeDetails(
        for item: MKMapItem,
        fallbackName: String,
        fallbackPlaceID: String
    ) -> PlaceDetails {
        let placemark = item.placemark
        return PlaceDetails(
            placeID: item.identifier?.rawValue ?? fallbackPlaceID,
            name: item.name ?? fallbackName,
            formattedAddress: [placemark.title, placemark.locality, placemark.country]
                .compactMap { $0 }
                .removingDuplicates()
                .joined(separator: ", "),
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
    }

    func mapFeaturePlaceID(for mapFeature: MapFeature) -> String {
        [
            "map-feature",
            mapFeature.title ?? "untitled",
            "\(mapFeature.coordinate.latitude)",
            "\(mapFeature.coordinate.longitude)"
        ]
        .joined(separator: ":")
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

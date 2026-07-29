#if canImport(GooglePlaces)
import CoreLocation
import GooglePlaces

@MainActor
final class GooglePlacesSearchService: NSObject, PlaceSearchService, GMSAutocompleteFetcherDelegate {
    private let placesClient = GMSPlacesClient.shared()
    private let fetcher: GMSAutocompleteFetcher
    private var suggestionContinuation: CheckedContinuation<[PlaceSuggestion], Error>?

    override init() {
        let filter = GMSAutocompleteFilter()
        filter.types = []
        fetcher = GMSAutocompleteFetcher(filter: filter)
        super.init()
        fetcher.delegate = self
    }

    func suggestions(for query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            suggestionContinuation?.resume(returning: [])
            suggestionContinuation = continuation
            fetcher.sourceTextHasChanged(trimmed)
        }
    }

    func details(for suggestion: PlaceSuggestion) async throws -> PlaceDetails {
        try await withCheckedThrowingContinuation { continuation in
            let fields: GMSPlaceField = [.placeID, .name, .formattedAddress, .coordinate]
            placesClient.fetchPlace(
                fromPlaceID: suggestion.placeID,
                placeFields: fields,
                sessionToken: nil
            ) { place, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let place else {
                    continuation.resume(throwing: PlaceSearchError.noDetails)
                    return
                }

                continuation.resume(
                    returning: PlaceDetails(
                        placeID: place.placeID ?? suggestion.placeID,
                        name: place.name ?? suggestion.primaryText,
                        formattedAddress: place.formattedAddress ?? suggestion.secondaryText,
                        latitude: place.coordinate.latitude,
                        longitude: place.coordinate.longitude
                    )
                )
            }
        }
    }

    nonisolated func didAutocomplete(with predictions: [GMSAutocompletePrediction]) {
        Task { @MainActor in
            let suggestions = predictions.map { prediction in
                return PlaceSuggestion(
                    placeID: prediction.placeID,
                    primaryText: prediction.attributedPrimaryText.string,
                    secondaryText: prediction.attributedSecondaryText?.string ?? ""
                )
            }
            suggestionContinuation?.resume(returning: suggestions)
            suggestionContinuation = nil
        }
    }

    nonisolated func didFailAutocompleteWithError(_ error: Error) {
        Task { @MainActor in
            suggestionContinuation?.resume(throwing: error)
            suggestionContinuation = nil
        }
    }
}
#endif

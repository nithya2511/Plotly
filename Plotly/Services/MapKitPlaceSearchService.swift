import CoreLocation
import Foundation
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

    func details(forFreeformQuery query: String, near coordinate: CLLocationCoordinate2D?) async throws -> PlaceDetails {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PlaceSearchError.noDetails
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
            )
        }

        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw PlaceSearchError.noDetails
        }

        return placeDetails(
            for: item,
            fallbackName: trimmed,
            fallbackPlaceID: "freeform:\(trimmed.lowercased())"
        )
    }

    func details(forMapLink link: String, near coordinate: CLLocationCoordinate2D?) async throws -> PlaceDetails {
        let normalizedLink = normalizedAppleMapsLink(link)
        if let details = placeDetails(fromAppleMapsURLString: normalizedLink) {
            return details
        }

        guard let url = URL(string: normalizedLink) else {
            throw PlaceSearchError.noDetails
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        var candidates = [normalizedLink]
        if let responseURL = response.url?.absoluteString {
            candidates.append(responseURL)
        }
        if let html = String(data: data, encoding: .utf8) {
            candidates.append(contentsOf: appleMapsURLStrings(in: html))
        }

        for candidate in candidates {
            if let details = placeDetails(fromAppleMapsURLString: candidate) {
                return details
            }
        }

        for candidate in candidates {
            if let lookupText = lookupText(fromAppleMapsURLString: candidate) {
                return try await details(forFreeformQuery: lookupText, near: coordinate)
            }
        }

        throw PlaceSearchError.noDetails
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

    func normalizedAppleMapsLink(_ link: String) -> String {
        var normalized = link
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>")))
            .replacingOccurrences(of: "&amp;", with: "&")

        if normalized.hasPrefix("https:/"), !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized.dropFirst("https:/".count)
        } else if normalized.hasPrefix("http:/"), !normalized.hasPrefix("http://") {
            normalized = "http://" + normalized.dropFirst("http:/".count)
        } else if normalized.lowercased().hasPrefix("maps.apple") {
            normalized = "https://" + normalized
        }

        return normalized
    }

    func placeDetails(fromAppleMapsURLString urlString: String) -> PlaceDetails? {
        let cleanURLString = normalizedAppleMapsLink(urlString)
        guard
            let components = URLComponents(string: cleanURLString),
            let queryItems = components.queryItems,
            let coordinate = coordinateValue(named: "ll", in: queryItems)
                ?? coordinateValue(named: "sll", in: queryItems)
        else {
            return nil
        }

        let name = queryValue(named: "q", in: queryItems)
        let address = queryValue(named: "address", in: queryItems)
            ?? queryValue(named: "daddr", in: queryItems)
        let title = name?.nilIfBlank ?? address?.nilIfBlank ?? "Map Location"
        let formattedAddress = address?.nilIfBlank ?? title

        return PlaceDetails(
            placeID: appleMapsPlaceID(title: title, coordinate: coordinate),
            name: title,
            formattedAddress: formattedAddress,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    func lookupText(fromAppleMapsURLString urlString: String) -> String? {
        let cleanURLString = normalizedAppleMapsLink(urlString)
        guard
            let components = URLComponents(string: cleanURLString),
            let queryItems = components.queryItems
        else {
            return nil
        }

        var parts: [String] = []
        for value in [
            queryValue(named: "q", in: queryItems),
            queryValue(named: "address", in: queryItems),
            queryValue(named: "daddr", in: queryItems)
        ].compactMap({ $0?.nilIfBlank }) where !parts.contains(value) {
            parts.append(value)
        }

        return parts.joined(separator: ", ").nilIfBlank
    }

    func appleMapsURLStrings(in text: String) -> [String] {
        let decoded = text.replacingOccurrences(of: "&amp;", with: "&")
        let pattern = #"https?:\\?/\\?/maps\.apple(?:\.com)?/[^\s"'<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
        return regex.matches(in: decoded, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: decoded) else { return nil }
            return String(decoded[matchRange])
        }
    }

    func queryValue(named name: String, in queryItems: [URLQueryItem]) -> String? {
        queryItems.first { $0.name == name }?.value?.nilIfBlank
    }

    func coordinateValue(named name: String, in queryItems: [URLQueryItem]) -> CLLocationCoordinate2D? {
        guard let value = queryValue(named: name, in: queryItems) else { return nil }
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard
            parts.count == 2,
            let latitude = Double(parts[0]),
            let longitude = Double(parts[1])
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func appleMapsPlaceID(title: String, coordinate: CLLocationCoordinate2D) -> String {
        [
            "apple-maps",
            title.lowercased(),
            coordinate.latitude.rounded(toPlaces: 6),
            coordinate.longitude.rounded(toPlaces: 6)
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

private extension Double {
    func rounded(toPlaces places: Int) -> String {
        String(format: "%.\(places)f", self)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

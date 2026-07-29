import Foundation

#if canImport(GoogleMaps)
import GoogleMaps
#endif

#if canImport(GooglePlaces)
import GooglePlaces
#endif

enum GoogleSDKBootstrap {
    private(set) static var isConfigured = false

    static var configuredAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String else {
            return nil
        }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$("), trimmed != "YOUR_GOOGLE_MAPS_API_KEY" else {
            return nil
        }

        return trimmed
    }

    @discardableResult
    static func configureIfPossible() -> Bool {
        guard !isConfigured, let apiKey = configuredAPIKey else {
            return isConfigured
        }

        #if canImport(GoogleMaps)
        GMSServices.provideAPIKey(apiKey)
        #endif

        #if canImport(GooglePlaces)
        GMSPlacesClient.provideAPIKey(apiKey)
        #endif

        isConfigured = true
        return true
    }
}

import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
final class HomeMapViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }

    @Published private(set) var suggestions: [PlaceSuggestion] = []
    @Published private(set) var stops: [PlanStopSnapshot] = []
    @Published private(set) var bookmarkedPlans: [PlanSnapshot] = []
    @Published private(set) var recentPlans: [PlanSnapshot] = []
    @Published private(set) var currentPlanID: UUID?
    @Published private(set) var planTitle = "Today's Route"
    @Published private(set) var isPlanFavorite = false
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    @Published private(set) var isSearching = false
    @Published private(set) var isAddingStop = false
    @Published private(set) var isImportingStops = false
    @Published private(set) var addressImportProgress: AddressImportProgress?
    @Published private(set) var pendingStopName: String?
    @Published private(set) var recentlyAddedStopID: UUID?
    @Published private(set) var routePlanningMode: RoutePlanningMode = .manual
    @Published private(set) var isNavigatingRoute = false
    @Published private(set) var activeNavigationStopID: UUID?
    @Published private(set) var visitedStopIDs: Set<UUID> = []
    @Published private(set) var mapFocusRequest: MapStopFocusRequest?
    @Published private(set) var deletedStopUndo: DeletedStopUndo?
    @Published var draftMapPinCoordinate: CLLocationCoordinate2D?
    @Published private(set) var draftMapPinDetails: PlaceDetails?
    @Published var selectedStopID: UUID?
    @Published var noteEditorStop: PlanStopSnapshot?
    @Published var noteDraft = ""
    @Published var errorMessage: String?

    var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedStop: PlanStopSnapshot? {
        guard let selectedStopID else { return nil }
        return stops.first(where: { $0.id == selectedStopID })
    }

    private let repository: PlanRepository
    private let searchService: PlaceSearchService
    private let locationService: LocationService
    private let navigationService: RouteNavigationService
    private var searchTask: Task<Void, Never>?
    private var mapFeatureDetailsTask: Task<Void, Never>?
    private var deleteUndoTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?

    init(
        repository: PlanRepository,
        searchService: PlaceSearchService? = nil,
        locationService: LocationService? = nil,
        navigationService: RouteNavigationService? = nil
    ) {
        self.repository = repository
        self.searchService = searchService ?? PlaceSearchServiceFactory.live()
        self.locationService = locationService ?? CoreLocationService()
        self.navigationService = navigationService ?? AppleMapsRouteNavigationService()
    }

    deinit {
        searchTask?.cancel()
        mapFeatureDetailsTask?.cancel()
        deleteUndoTask?.cancel()
        locationTask?.cancel()
        let locationService = locationService
        Task { @MainActor in
            locationService.cancelCurrentRequest()
        }
    }

    func load() {
        do {
            apply(try repository.loadCurrentPlan())
            refreshBookmarkedPlans()
            refreshRecentPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.loadRoute
        }

        locationTask?.cancel()
        locationTask = Task {
            let coordinate = await locationService.requestCurrentLocation()
            guard !Task.isCancelled else { return }
            userCoordinate = coordinate
        }
    }

    func suspendForBackground() {
        searchTask?.cancel()
        searchTask = nil
        mapFeatureDetailsTask?.cancel()
        mapFeatureDetailsTask = nil
        locationTask?.cancel()
        locationTask = nil
        locationService.cancelCurrentRequest()
        isSearching = false
        suggestions = []
    }

    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        suggestions = []
        isSearching = false
    }

    func addStop(from suggestion: PlaceSuggestion) {
        searchTask?.cancel()
        isAddingStop = true
        pendingStopName = suggestion.primaryText
        errorMessage = nil

        Task {
            defer {
                isAddingStop = false
                pendingStopName = nil
            }

            do {
                let details = try await searchService.details(for: suggestion)
                let plan = try repository.addStop(details)
                apply(plan)
                routePlanningMode = .manual
                resetNavigationProgress()
                if let added = plan.stops.first(where: { $0.placeID == details.placeID }) {
                    selectedStopID = added.id
                    recentlyAddedStopID = added.id
                    mapFocusRequest = MapStopFocusRequest(stopID: added.id)
                }
                clearSearch()
            } catch {
                errorMessage = UserFacingErrorMessage.addStop
            }
        }
    }

    func importStops(from text: String) async -> AddressImportResult {
        let importItems = Self.importAddressItems(from: text)
        guard !importItems.isEmpty else {
            errorMessage = "Paste at least one address to import."
            return AddressImportResult(totalCount: 0, addedCount: 0, failedAddresses: [])
        }

        searchTask?.cancel()
        suggestions = []
        isSearching = false
        isAddingStop = true
        isImportingStops = true
        errorMessage = nil
        var addedCount = 0
        var failedAddresses: [String] = []
        var lastAddedStopID: UUID?

        defer {
            isAddingStop = false
            isImportingStops = false
            pendingStopName = nil
            addressImportProgress = nil
        }

        for (index, item) in importItems.enumerated() {
            guard !Task.isCancelled else { break }
            addressImportProgress = AddressImportProgress(
                currentIndex: index + 1,
                totalCount: importItems.count,
                currentAddress: item.displayText
            )
            pendingStopName = item.displayText

            do {
                let existingStopIDs = Set(stops.map(\.id))
                let details = if let directDetails = item.directDetails {
                    directDetails
                } else if let mapLink = item.mapLink {
                    try await searchService.details(forMapLink: mapLink, near: userCoordinate)
                } else {
                    try await searchService.details(forFreeformQuery: item.lookupText, near: userCoordinate)
                }
                guard !Task.isCancelled else { break }
                let plan = try repository.addStop(details)
                apply(plan)
                routePlanningMode = .manual
                resetNavigationProgress()

                if let addedStop = stops.first(where: { !existingStopIDs.contains($0.id) }) {
                    addedCount += 1
                    lastAddedStopID = addedStop.id
                }
            } catch is CancellationError {
                break
            } catch {
                failedAddresses.append(item.displayText)
            }
        }

        if let lastAddedStopID {
            selectedStopID = lastAddedStopID
            recentlyAddedStopID = lastAddedStopID
            mapFocusRequest = MapStopFocusRequest(stopID: lastAddedStopID)
        }

        refreshBookmarkedPlans()
        refreshRecentPlans()

        let result = AddressImportResult(
            totalCount: importItems.count,
            addedCount: addedCount,
            failedAddresses: failedAddresses
        )

        if result.addedCount == 0 {
            errorMessage = UserFacingErrorMessage.importAddresses
        } else if !result.failedAddresses.isEmpty {
            errorMessage = result.summary
        }

        return result
    }

    func stageMapPin(at coordinate: CLLocationCoordinate2D) {
        searchTask?.cancel()
        mapFeatureDetailsTask?.cancel()
        clearSearch()
        draftMapPinCoordinate = coordinate
        draftMapPinDetails = nil
        selectedStopID = nil
        errorMessage = nil
    }

    func stageMapFeature(_ mapFeature: MapFeature) {
        searchTask?.cancel()
        mapFeatureDetailsTask?.cancel()
        clearSearch()

        let fallbackDetails = PlaceDetails(
            placeID: mapFeaturePlaceID(for: mapFeature),
            name: mapFeature.title?.nilIfBlank ?? "Selected Place",
            formattedAddress: formattedCoordinate(mapFeature.coordinate),
            latitude: mapFeature.coordinate.latitude,
            longitude: mapFeature.coordinate.longitude
        )
        stageMapPlace(fallbackDetails)

        mapFeatureDetailsTask = Task {
            do {
                let details = try await searchService.details(for: mapFeature)
                guard !Task.isCancelled else { return }
                stageMapPlace(details)
            } catch {
                guard !Task.isCancelled else { return }
                draftMapPinDetails = fallbackDetails
            }
        }
    }

    func stageMapPlace(_ details: PlaceDetails) {
        draftMapPinCoordinate = details.coordinate
        draftMapPinDetails = details
        selectedStopID = nil
        errorMessage = nil
    }

    func cancelDraftMapPin() {
        mapFeatureDetailsTask?.cancel()
        draftMapPinCoordinate = nil
        draftMapPinDetails = nil
    }

    func confirmDraftMapPin() {
        guard let coordinate = draftMapPinCoordinate else { return }
        mapFeatureDetailsTask?.cancel()
        isAddingStop = true
        pendingStopName = draftMapPinDetails?.name ?? "Dropped Pin"
        errorMessage = nil

        defer {
            isAddingStop = false
            pendingStopName = nil
        }

        do {
            let details = draftMapPinDetails ?? PlaceDetails(
                placeID: manualPinPlaceID(for: coordinate),
                name: "Dropped Pin",
                formattedAddress: formattedCoordinate(coordinate),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let plan = try repository.addStop(details)
            apply(plan)
            routePlanningMode = .manual
            resetNavigationProgress()
            draftMapPinCoordinate = nil
            draftMapPinDetails = nil
            if let added = plan.stops.first(where: { $0.placeID == details.placeID }) {
                selectedStopID = added.id
                recentlyAddedStopID = added.id
                mapFocusRequest = MapStopFocusRequest(stopID: added.id)
            }
        } catch {
            errorMessage = UserFacingErrorMessage.addMapPin
        }
    }

    func saveRouteDetails(title: String, isFavorite: Bool) {
        do {
            apply(try repository.updatePlanDetails(title: title, isFavorite: isFavorite))
            refreshBookmarkedPlans()
            refreshRecentPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.saveRoute
        }
    }

    func toggleRouteFavorite() {
        saveRouteDetails(title: planTitle, isFavorite: !isPlanFavorite)
    }

    func selectBookmarkedPlan(_ plan: PlanSnapshot) {
        selectRecentPlan(plan)
    }

    func selectRecentPlan(_ plan: PlanSnapshot) {
        do {
            apply(try repository.selectPlan(id: plan.id))
            routePlanningMode = .manual
            resetNavigationProgress()
            refreshBookmarkedPlans()
            refreshRecentPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.openRoute
        }
    }

    func createNewRoute() {
        do {
            apply(try repository.createNewPlan())
            routePlanningMode = .manual
            selectedStopID = nil
            recentlyAddedStopID = nil
            resetNavigationProgress()
            refreshBookmarkedPlans()
            refreshRecentPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.createRoute
        }
    }

    func discardCurrentRouteAndCreateNew() {
        do {
            apply(try repository.discardCurrentPlanAndCreateNew())
            routePlanningMode = .manual
            selectedStopID = nil
            recentlyAddedStopID = nil
            resetNavigationProgress()
            refreshBookmarkedPlans()
            refreshRecentPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.createRoute
        }
    }

    func startEditingNote(for stop: PlanStopSnapshot) {
        noteEditorStop = stop
        noteDraft = stop.note
    }

    func saveNote() {
        guard let stop = noteEditorStop else { return }

        do {
            apply(try repository.updateStopNote(id: stop.id, note: noteDraft))
            noteEditorStop = nil
            noteDraft = ""
        } catch {
            errorMessage = UserFacingErrorMessage.saveNote
        }
    }

    func deleteStop(_ stop: PlanStopSnapshot) {
        let undo = DeletedStopUndo(planID: currentPlanID, stop: stop)
        do {
            apply(try repository.removeStop(id: stop.id))
            routePlanningMode = .manual
            resetNavigationProgress()
            if selectedStopID == stop.id {
                selectedStopID = nil
            }
            if recentlyAddedStopID == stop.id {
                recentlyAddedStopID = nil
            }
            deletedStopUndo = undo
            refreshBookmarkedPlans()
            refreshRecentPlans()
            scheduleDeleteUndoExpiry(for: undo.id)
        } catch {
            errorMessage = UserFacingErrorMessage.removeStop
        }
    }

    func undoDeleteStop() {
        guard let deletedStopUndo else { return }

        guard deletedStopUndo.planID == currentPlanID else {
            clearDeleteUndo()
            return
        }

        deleteUndoTask?.cancel()

        do {
            apply(try repository.restoreStop(deletedStopUndo.stop))
            routePlanningMode = .manual
            resetNavigationProgress()
            selectedStopID = deletedStopUndo.stop.id
            mapFocusRequest = MapStopFocusRequest(stopID: deletedStopUndo.stop.id)
            self.deletedStopUndo = nil
            refreshBookmarkedPlans()
            refreshRecentPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.restoreStop
        }
    }

    func clearDeleteUndo() {
        deleteUndoTask?.cancel()
        deletedStopUndo = nil
    }

    func moveStops(from source: IndexSet, to destination: Int) {
        do {
            apply(try repository.moveStops(from: source, to: destination))
            routePlanningMode = .manual
            resetNavigationProgress()
        } catch {
            errorMessage = UserFacingErrorMessage.reorderStops
        }
    }

    func moveStop(_ draggedID: UUID, to targetID: UUID) {
        guard
            let sourceIndex = stops.firstIndex(where: { $0.id == draggedID }),
            let targetIndex = stops.firstIndex(where: { $0.id == targetID }),
            sourceIndex != targetIndex
        else {
            return
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        moveStops(from: IndexSet(integer: sourceIndex), to: destination)
    }

    func applyRoutePlan(
        mode: RoutePlanningMode,
        fixedStartStopID: UUID?,
        fixedEndStopID: UUID?
    ) {
        let orderedStopIDs = RoutePlanner.orderedStopIDs(
            stops: stops,
            mode: mode,
            userCoordinate: userCoordinate,
            fixedStartStopID: fixedStartStopID,
            fixedEndStopID: fixedEndStopID
        )

        do {
            apply(try repository.reorderStops(orderedStopIDs))
            routePlanningMode = mode
            resetNavigationProgress()
        } catch {
            errorMessage = UserFacingErrorMessage.planRoute
        }
    }

    func startRouteNavigation() {
        guard let nextStop = nextUnvisitedStop() else {
            isNavigatingRoute = false
            activeNavigationStopID = nil
            return
        }

        goToStop(nextStop)
    }

    func advanceRouteNavigation() {
        guard isNavigatingRoute, let activeNavigationStopID else {
            startRouteNavigation()
            return
        }

        do {
            apply(try repository.updateStopCompletion(id: activeNavigationStopID, isCompleted: true))
            self.activeNavigationStopID = nil
            focusNextNavigationStop()
        } catch {
            errorMessage = UserFacingErrorMessage.updateProgress
        }
    }

    func stopRouteNavigation() {
        isNavigatingRoute = false
        activeNavigationStopID = nil
        selectedStopID = nextUnvisitedStop()?.id
    }

    func markStopCompleted(_ stop: PlanStopSnapshot) {
        do {
            apply(try repository.updateStopCompletion(id: stop.id, isCompleted: true))
            if activeNavigationStopID == stop.id {
                activeNavigationStopID = nil
            }
            focusNextNavigationStop()
        } catch {
            errorMessage = UserFacingErrorMessage.updateProgress
        }
    }

    func markStopIncomplete(_ stop: PlanStopSnapshot) {
        do {
            apply(try repository.updateStopCompletion(id: stop.id, isCompleted: false))
            if activeNavigationStopID == stop.id {
                activeNavigationStopID = nil
                isNavigatingRoute = false
            }
            selectedStopID = stop.id
        } catch {
            errorMessage = UserFacingErrorMessage.updateProgress
        }
    }

    func goToStop(_ stop: PlanStopSnapshot) {
        resetCompletionFromStopIfNeeded(stop)
        isNavigatingRoute = true
        activeNavigationStopID = stop.id
        selectedStopID = stop.id
        let didOpenDirections = navigationService.openDirections(to: stop)
        if !didOpenDirections {
            isNavigatingRoute = nextUnvisitedStop() != nil
            activeNavigationStopID = nil
            errorMessage = UserFacingErrorMessage.openDirections
        }
    }

    func goToNextNavigationStop() {
        guard let nextStop = nextNavigationStop() else { return }
        goToStop(nextStop)
    }

    func completeActiveNavigationStopOnReturn() {
        guard let activeNavigationStopID else { return }
        do {
            apply(try repository.updateStopCompletion(id: activeNavigationStopID, isCompleted: true))
            self.activeNavigationStopID = nil
            focusNextNavigationStop()
        } catch {
            errorMessage = UserFacingErrorMessage.updateProgress
        }
    }

    func nextNavigationStop() -> PlanStopSnapshot? {
        nextUnvisitedStop()
    }

    private func nextUnvisitedStop(after index: Int? = nil) -> PlanStopSnapshot? {
        let startIndex = index.map { $0 + 1 } ?? stops.startIndex
        guard startIndex < stops.endIndex else {
            return nil
        }

        return stops[startIndex...].first { !visitedStopIDs.contains($0.id) }
    }

    private func resetCompletionFromStopIfNeeded(_ stop: PlanStopSnapshot) {
        guard let stopIndex = stops.firstIndex(where: { $0.id == stop.id }) else { return }
        let stopsToReset = stops[stopIndex...].filter { visitedStopIDs.contains($0.id) }
        guard !stopsToReset.isEmpty else { return }

        do {
            var updatedPlan: PlanSnapshot?
            for stop in stopsToReset {
                updatedPlan = try repository.updateStopCompletion(id: stop.id, isCompleted: false)
            }
            if let updatedPlan {
                apply(updatedPlan)
            }
        } catch {
            errorMessage = UserFacingErrorMessage.updateProgress
        }
    }

    private func focusNextNavigationStop() {
        if let nextStop = nextUnvisitedStop() {
            isNavigatingRoute = true
            selectedStopID = nextStop.id
        } else {
            isNavigatingRoute = false
            selectedStopID = nil
        }
    }

    func refreshBookmarkedPlans() {
        do {
            bookmarkedPlans = try repository.loadBookmarkedPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.loadBookmarks
        }
    }

    func refreshRecentPlans() {
        do {
            recentPlans = try repository.loadRecentPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.loadRoutes
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                let results = try await searchService.suggestions(for: query, near: userCoordinate)
                guard !Task.isCancelled else { return }
                suggestions = results
                isSearching = false
            } catch is CancellationError {
                isSearching = false
            } catch {
                suggestions = []
                isSearching = false
                errorMessage = UserFacingErrorMessage.placeSearch
            }
        }
    }

    private func apply(_ plan: PlanSnapshot) {
        currentPlanID = plan.id
        planTitle = plan.title
        isPlanFavorite = plan.isFavorite
        stops = plan.stops.sorted { $0.sortIndex < $1.sortIndex }
        visitedStopIDs = Set(stops.filter(\.isCompleted).map(\.id))
    }

    private func resetNavigationProgress() {
        isNavigatingRoute = false
        activeNavigationStopID = nil
    }

    private func scheduleDeleteUndoExpiry(for undoID: UUID) {
        deleteUndoTask?.cancel()
        deleteUndoTask = Task {
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }

            guard deletedStopUndo?.id == undoID else { return }
            deletedStopUndo = nil
        }
    }

    private func manualPinPlaceID(for coordinate: CLLocationCoordinate2D) -> String {
        "manual-pin:\(coordinate.latitude.rounded(toPlaces: 6)),\(coordinate.longitude.rounded(toPlaces: 6))"
    }

    private func mapFeaturePlaceID(for mapFeature: MapFeature) -> String {
        [
            "map-feature",
            mapFeature.title?.nilIfBlank ?? "untitled",
            mapFeature.coordinate.latitude.rounded(toPlaces: 6),
            mapFeature.coordinate.longitude.rounded(toPlaces: 6)
        ]
        .joined(separator: ":")
    }

    private func formattedCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude.rounded(toPlaces: 5)), \(coordinate.longitude.rounded(toPlaces: 5))"
    }

    private static let importTrimCharacters = CharacterSet.whitespacesAndNewlines
        .union(.controlCharacters)
        .union(CharacterSet(charactersIn: "\u{00A0}\u{200B}\u{FEFF}"))

    private static func importAddressItems(from text: String) -> [AddressImportItem] {
        text
            .components(separatedBy: .newlines)
            .map { cleanedImportAddressLine($0) }
            .filter { !$0.isEmpty }
            .map { importAddressItem(from: $0) }
    }

    private static func cleanedImportAddressLine(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: importTrimCharacters)

        let bulletPrefixes: Set<Character> = ["-", "*", "•"]
        while let first = cleaned.first, bulletPrefixes.contains(first) {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: importTrimCharacters)
        }

        if let separatorIndex = cleaned.firstIndex(where: { $0 == "." || $0 == ")" }) {
            let prefix = cleaned[..<separatorIndex]
            if !prefix.isEmpty, prefix.allSatisfy(\.isNumber), prefix.count <= 3 {
                cleaned = String(cleaned[cleaned.index(after: separatorIndex)...])
                    .trimmingCharacters(in: importTrimCharacters)
            }
        }

        return cleaned
    }

    private static func importAddressItem(from line: String) -> AddressImportItem {
        guard let mapLink = appleMapsLink(in: line) else {
            return AddressImportItem(originalText: line, lookupText: line, mapLink: nil, directDetails: nil)
        }

        guard let components = URLComponents(string: normalizedMapLink(mapLink)) else {
            return AddressImportItem(originalText: line, lookupText: line, mapLink: nil, directDetails: nil)
        }

        let queryItems = components.queryItems ?? []
        let name = queryValue(named: "q", in: queryItems)
        let address = queryValue(named: "address", in: queryItems)
            ?? queryValue(named: "daddr", in: queryItems)
        let coordinate = coordinateValue(named: "ll", in: queryItems)
            ?? coordinateValue(named: "sll", in: queryItems)

        if let coordinate {
            let title = name?.nilIfBlank ?? address?.nilIfBlank ?? "Map Location"
            let formattedAddress = address?.nilIfBlank ?? title
            let details = PlaceDetails(
                placeID: appleMapsPlaceID(title: title, coordinate: coordinate),
                name: title,
                formattedAddress: formattedAddress,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            return AddressImportItem(originalText: line, lookupText: title, mapLink: nil, directDetails: details)
        }

        var lookupParts: [String] = []
        for value in [name?.nilIfBlank, address?.nilIfBlank].compactMap({ $0 }) where !lookupParts.contains(value) {
            lookupParts.append(value)
        }
        let lookupText = lookupParts.joined(separator: ", ")
        return AddressImportItem(
            originalText: line,
            lookupText: lookupText.nilIfBlank ?? line,
            mapLink: normalizedMapLink(mapLink),
            directDetails: nil
        )
    }

    private static func appleMapsLink(in line: String) -> String? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        if let token = tokens.first(where: { isAppleMapsLinkText($0) }) {
            return token.trimmingCharacters(in: importTrimCharacters.union(CharacterSet(charactersIn: "<>")))
        }

        guard let range = line.range(of: "maps.apple", options: .caseInsensitive) else {
            return nil
        }

        return String(line[range.lowerBound...]).trimmingCharacters(in: importTrimCharacters)
    }

    private static func isAppleMapsLinkText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("maps.apple.com") || lowercased.contains("maps.apple/")
    }

    private static func normalizedMapLink(_ link: String) -> String {
        var normalized = link.trimmingCharacters(in: importTrimCharacters.union(CharacterSet(charactersIn: "<>")))
        if normalized.hasPrefix("https:/"), !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized.dropFirst("https:/".count)
        } else if normalized.hasPrefix("http:/"), !normalized.hasPrefix("http://") {
            normalized = "http://" + normalized.dropFirst("http:/".count)
        } else if normalized.lowercased().hasPrefix("maps.apple") {
            normalized = "https://" + normalized
        }
        return normalized
    }

    private static func queryValue(named name: String, in queryItems: [URLQueryItem]) -> String? {
        queryItems.first { $0.name == name }?.value?.nilIfBlank
    }

    private static func coordinateValue(named name: String, in queryItems: [URLQueryItem]) -> CLLocationCoordinate2D? {
        guard let value = queryValue(named: name, in: queryItems) else { return nil }
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: importTrimCharacters) }
        guard
            parts.count == 2,
            let latitude = Double(parts[0]),
            let longitude = Double(parts[1])
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func appleMapsPlaceID(title: String, coordinate: CLLocationCoordinate2D) -> String {
        [
            "apple-maps",
            title.lowercased(),
            coordinate.latitude.rounded(toPlaces: 6),
            coordinate.longitude.rounded(toPlaces: 6)
        ]
        .joined(separator: ":")
    }
}

struct MapStopFocusRequest: Equatable {
    let id = UUID()
    let stopID: UUID
}

struct AddressImportProgress: Equatable {
    let currentIndex: Int
    let totalCount: Int
    let currentAddress: String
}

struct AddressImportResult: Equatable {
    let totalCount: Int
    let addedCount: Int
    let failedAddresses: [String]

    var failedCount: Int {
        failedAddresses.count
    }

    var summary: String {
        guard failedCount > 0 else {
            return "Added \(addedCount) \(addedCount == 1 ? "stop" : "stops")."
        }

        let failedPreview = failedAddresses.prefix(2).joined(separator: ", ")
        let extraCount = max(failedAddresses.count - 2, 0)
        let suffix = extraCount > 0 ? " and \(extraCount) more" : ""
        return "Added \(addedCount) \(addedCount == 1 ? "stop" : "stops"). Could not find: \(failedPreview)\(suffix)."
    }
}

private struct AddressImportItem: Equatable {
    let originalText: String
    let lookupText: String
    let mapLink: String?
    let directDetails: PlaceDetails?

    var displayText: String {
        directDetails?.name ?? lookupText
    }
}

struct DeletedStopUndo: Identifiable, Equatable {
    let id = UUID()
    let planID: UUID?
    let stop: PlanStopSnapshot
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

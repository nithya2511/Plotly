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
    @Published private(set) var currentPlanID: UUID?
    @Published private(set) var planTitle = "Today's Route"
    @Published private(set) var isPlanFavorite = false
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    @Published private(set) var isSearching = false
    @Published private(set) var isAddingStop = false
    @Published private(set) var pendingStopName: String?
    @Published private(set) var recentlyAddedStopID: UUID?
    @Published private(set) var routePlanningMode: RoutePlanningMode = .manual
    @Published private(set) var isNavigatingRoute = false
    @Published private(set) var activeNavigationStopID: UUID?
    @Published private(set) var visitedStopIDs: Set<UUID> = []
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
    }

    func load() {
        do {
            apply(try repository.loadCurrentPlan())
            refreshBookmarkedPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.loadRoute
        }

        Task {
            userCoordinate = await locationService.requestCurrentLocation()
        }
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
                }
                clearSearch()
            } catch {
                errorMessage = UserFacingErrorMessage.addStop
            }
        }
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
            }
        } catch {
            errorMessage = UserFacingErrorMessage.addMapPin
        }
    }

    func saveRouteDetails(title: String, isFavorite: Bool) {
        do {
            apply(try repository.updatePlanDetails(title: title, isFavorite: isFavorite))
            refreshBookmarkedPlans()
        } catch {
            errorMessage = UserFacingErrorMessage.saveRoute
        }
    }

    func toggleRouteFavorite() {
        saveRouteDetails(title: planTitle, isFavorite: !isPlanFavorite)
    }

    func selectBookmarkedPlan(_ plan: PlanSnapshot) {
        do {
            apply(try repository.selectPlan(id: plan.id))
            routePlanningMode = .manual
            resetNavigationProgress()
            refreshBookmarkedPlans()
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

    func remove(_ stop: PlanStopSnapshot) {
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
        } catch {
            errorMessage = UserFacingErrorMessage.removeStop
        }
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

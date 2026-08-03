import Combine
import CoreLocation
import Foundation

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
    }

    func load() {
        do {
            apply(try repository.loadCurrentPlan())
            refreshBookmarkedPlans()
        } catch {
            errorMessage = error.localizedDescription
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
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveRouteDetails(title: String, isFavorite: Bool) {
        do {
            apply(try repository.updatePlanDetails(title: title, isFavorite: isFavorite))
            refreshBookmarkedPlans()
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func moveStops(from source: IndexSet, to destination: Int) {
        do {
            apply(try repository.moveStops(from: source, to: destination))
            routePlanningMode = .manual
            resetNavigationProgress()
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func startRouteNavigation() {
        navigateToNextUnvisitedStop()
    }

    func advanceRouteNavigation() {
        guard isNavigatingRoute, let activeNavigationStopID else {
            startRouteNavigation()
            return
        }

        visitedStopIDs.insert(activeNavigationStopID)
        let activeIndex = stops.firstIndex { $0.id == activeNavigationStopID }
        navigateToNextUnvisitedStop(after: activeIndex)
    }

    func stopRouteNavigation() {
        isNavigatingRoute = false
        activeNavigationStopID = nil
    }

    func markStopCompleted(_ stop: PlanStopSnapshot) {
        visitedStopIDs.insert(stop.id)
        let completedIndex = stops.firstIndex { $0.id == stop.id }
        navigateToNextUnvisitedStop(after: completedIndex)
    }

    func markStopIncomplete(_ stop: PlanStopSnapshot) {
        visitedStopIDs.remove(stop.id)
        if activeNavigationStopID == stop.id {
            activeNavigationStopID = nil
            isNavigatingRoute = false
        }
    }

    func nextNavigationStop() -> PlanStopSnapshot? {
        nextUnvisitedStop()
    }

    private func navigateToNextUnvisitedStop(after index: Int? = nil) {
        guard let nextStop = nextUnvisitedStop(after: index) else {
            isNavigatingRoute = false
            activeNavigationStopID = nil
            return
        }

        isNavigatingRoute = true
        activeNavigationStopID = nextStop.id
        selectedStopID = nextStop.id
        navigationService.openDirections(to: nextStop)
    }

    private func nextUnvisitedStop(after index: Int? = nil) -> PlanStopSnapshot? {
        let startIndex = index.map { $0 + 1 } ?? stops.startIndex
        guard startIndex < stops.endIndex else {
            return nil
        }

        return stops[startIndex...].first { !visitedStopIDs.contains($0.id) }
    }

    func refreshBookmarkedPlans() {
        do {
            bookmarkedPlans = try repository.loadBookmarkedPlans()
        } catch {
            errorMessage = error.localizedDescription
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
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ plan: PlanSnapshot) {
        currentPlanID = plan.id
        planTitle = plan.title
        isPlanFavorite = plan.isFavorite
        stops = plan.stops.sorted { $0.sortIndex < $1.sortIndex }
    }

    private func resetNavigationProgress() {
        isNavigatingRoute = false
        activeNavigationStopID = nil
        visitedStopIDs = []
    }
}

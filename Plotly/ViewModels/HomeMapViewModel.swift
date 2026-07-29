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
    @Published private(set) var planTitle = "Today's Route"
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    @Published private(set) var isSearching = false
    @Published private(set) var isAddingStop = false
    @Published private(set) var pendingStopName: String?
    @Published private(set) var recentlyAddedStopID: UUID?
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
    private var searchTask: Task<Void, Never>?

    init(
        repository: PlanRepository,
        searchService: PlaceSearchService? = nil,
        locationService: LocationService? = nil
    ) {
        self.repository = repository
        self.searchService = searchService ?? PlaceSearchServiceFactory.live()
        self.locationService = locationService ?? CoreLocationService()
    }

    deinit {
        searchTask?.cancel()
    }

    func load() {
        do {
            apply(try repository.loadCurrentPlan())
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
        planTitle = plan.title
        stops = plan.stops.sorted { $0.sortIndex < $1.sortIndex }
    }
}

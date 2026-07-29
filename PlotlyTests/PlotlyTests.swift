import CoreLocation
import SwiftData
import XCTest
@testable import Plotly

@MainActor
final class PlotlyTests: XCTestCase {
    func testSwiftDataRepositoryCreatesCurrentPlanAndPreventsDuplicateStops() throws {
        let store = try makeStore()
        let repository = store.repository
        let place = PlaceDetails(
            placeID: "google-place-1",
            name: "Museum Island",
            formattedAddress: "Berlin, Germany",
            latitude: 52.5169,
            longitude: 13.4010
        )

        let emptyPlan = try repository.loadCurrentPlan()
        XCTAssertEqual(emptyPlan.title, "Today's Route")
        XCTAssertTrue(emptyPlan.stops.isEmpty)

        let firstSave = try repository.addStop(place)
        XCTAssertEqual(firstSave.stops.count, 1)
        XCTAssertEqual(firstSave.stops.first?.name, "Museum Island")

        let duplicateSave = try repository.addStop(place)
        XCTAssertEqual(duplicateSave.stops.count, 1)
    }

    func testSwiftDataRepositoryUpdatesNoteAndRemovesStop() throws {
        let store = try makeStore()
        let repository = store.repository
        let place = PlaceDetails(
            placeID: "google-place-2",
            name: "Apartment Viewing",
            formattedAddress: "Main Street 10",
            latitude: 52.5100,
            longitude: 13.3900
        )

        let plan = try repository.addStop(place)
        let stopID = try XCTUnwrap(plan.stops.first?.id)

        let withNote = try repository.updateStopNote(id: stopID, note: "Ask about morning sunlight.")
        XCTAssertEqual(withNote.stops.first?.note, "Ask about morning sunlight.")

        let afterRemoval = try repository.removeStop(id: stopID)
        XCTAssertTrue(afterRemoval.stops.isEmpty)
    }

    func testViewModelSearchesAndAddsSelectedSuggestion() async throws {
        let suggestion = PlaceSuggestion(
            placeID: "google-place-3",
            primaryText: "Coffee House",
            secondaryText: "Kreuzberg"
        )
        let details = PlaceDetails(
            placeID: suggestion.placeID,
            name: suggestion.primaryText,
            formattedAddress: suggestion.secondaryText,
            latitude: 52.4999,
            longitude: 13.4210
        )
        let repository = MockPlanRepository()
        let searchService = MockPlaceSearchService(suggestions: [suggestion], details: details)
        let viewModel = HomeMapViewModel(
            repository: repository,
            searchService: searchService,
            locationService: MockLocationService()
        )

        viewModel.load()
        viewModel.searchText = "Coffee"
        try await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertEqual(viewModel.suggestions, [suggestion])

        viewModel.addStop(from: suggestion)
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(viewModel.stops.count, 1)
        XCTAssertEqual(viewModel.stops.first?.placeID, suggestion.placeID)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertNotNil(viewModel.selectedStopID)
    }

    private func makeStore() throws -> RepositoryTestStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Plan.self, PlanStop.self, configurations: configuration)
        return RepositoryTestStore(
            container: container,
            repository: SwiftDataPlanRepository(modelContext: container.mainContext)
        )
    }
}

private struct RepositoryTestStore {
    let container: ModelContainer
    let repository: SwiftDataPlanRepository
}

@MainActor
private final class MockPlanRepository: PlanRepository {
    private var plan = PlanSnapshot(id: UUID(), title: "Today's Route", stops: [])

    func loadCurrentPlan() throws -> PlanSnapshot {
        plan
    }

    func addStop(_ place: PlaceDetails) throws -> PlanSnapshot {
        if !plan.stops.contains(where: { $0.placeID == place.placeID }) {
            let stop = PlanStopSnapshot(
                id: UUID(),
                placeID: place.placeID,
                name: place.name,
                formattedAddress: place.formattedAddress,
                latitude: place.latitude,
                longitude: place.longitude,
                note: "",
                sortIndex: plan.stops.count
            )
            plan = PlanSnapshot(id: plan.id, title: plan.title, stops: plan.stops + [stop])
        }
        return plan
    }

    func updateStopNote(id: UUID, note: String) throws -> PlanSnapshot {
        let updatedStops = plan.stops.map { stop in
            guard stop.id == id else { return stop }
            return PlanStopSnapshot(
                id: stop.id,
                placeID: stop.placeID,
                name: stop.name,
                formattedAddress: stop.formattedAddress,
                latitude: stop.latitude,
                longitude: stop.longitude,
                note: note,
                sortIndex: stop.sortIndex
            )
        }
        plan = PlanSnapshot(id: plan.id, title: plan.title, stops: updatedStops)
        return plan
    }

    func removeStop(id: UUID) throws -> PlanSnapshot {
        plan = PlanSnapshot(
            id: plan.id,
            title: plan.title,
            stops: plan.stops.filter { $0.id != id }
        )
        return plan
    }
}

@MainActor
private final class MockPlaceSearchService: PlaceSearchService {
    private let stubSuggestions: [PlaceSuggestion]
    private let stubDetails: PlaceDetails

    init(suggestions: [PlaceSuggestion], details: PlaceDetails) {
        self.stubSuggestions = suggestions
        self.stubDetails = details
    }

    func suggestions(for query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceSuggestion] {
        stubSuggestions
    }

    func details(for suggestion: PlaceSuggestion) async throws -> PlaceDetails {
        stubDetails
    }
}

@MainActor
private final class MockLocationService: LocationService {
    func requestCurrentLocation() async -> CLLocationCoordinate2D? {
        nil
    }
}

import CoreLocation
import SwiftData
import XCTest
@testable import Plotly

@MainActor
final class PlotlyTests: XCTestCase {
    func testAccountRepositoryCreatesAndReloadsLocalUser() throws {
        let store = try makeStore()
        let accountRepository = SwiftDataAccountRepository(modelContext: store.container.mainContext)

        let account = try accountRepository.signIn(displayName: "Nithya", email: "NITHYA@example.com")
        let reloaded = try XCTUnwrap(try accountRepository.account(id: account.id))

        XCTAssertEqual(account.displayName, "Nithya")
        XCTAssertEqual(account.email, "nithya@example.com")
        XCTAssertEqual(reloaded, account)
    }

    func testLoginViewModelCanContinueAsGuest() {
        var skippedAccount: UserAccountSnapshot?
        let viewModel = LoginViewModel(
            repository: MockAccountRepository(),
            onSignedIn: { _ in },
            onSkipped: { skippedAccount = $0 }
        )

        viewModel.continueAsGuest()

        XCTAssertEqual(skippedAccount, .guest)
        XCTAssertTrue(skippedAccount?.isGuest == true)
    }

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

    func testSwiftDataRepositoryUpdatesRouteDetails() throws {
        let store = try makeStore()
        let repository = store.repository

        let updated = try repository.updatePlanDetails(title: "Berlin Weekend", isFavorite: true)

        XCTAssertEqual(updated.title, "Berlin Weekend")
        XCTAssertTrue(updated.isFavorite)

        let reloaded = try repository.loadCurrentPlan()
        XCTAssertEqual(reloaded.title, "Berlin Weekend")
        XCTAssertTrue(reloaded.isFavorite)
    }

    func testSwiftDataRepositoryMovesStopsAndPersistsOrder() throws {
        let store = try makeStore()
        let repository = store.repository

        _ = try repository.addStop(
            PlaceDetails(
                placeID: "start",
                name: "Start",
                formattedAddress: "Start Address",
                latitude: 52.1,
                longitude: 13.1
            )
        )
        _ = try repository.addStop(
            PlaceDetails(
                placeID: "middle",
                name: "Middle",
                formattedAddress: "Middle Address",
                latitude: 52.2,
                longitude: 13.2
            )
        )
        _ = try repository.addStop(
            PlaceDetails(
                placeID: "destination",
                name: "Destination",
                formattedAddress: "Destination Address",
                latitude: 52.3,
                longitude: 13.3
            )
        )

        let reordered = try repository.moveStops(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(reordered.stops.map(\.placeID), ["destination", "start", "middle"])
        XCTAssertEqual(reordered.stops.map(\.sortIndex), [0, 1, 2])

        let reloaded = try repository.loadCurrentPlan()
        XCTAssertEqual(reloaded.stops.map(\.placeID), ["destination", "start", "middle"])
    }

    func testSwiftDataRepositoryReordersStopsByIDAndPersistsOrder() throws {
        let store = try makeStore()
        let repository = store.repository

        let firstPlan = try repository.addStop(
            PlaceDetails(
                placeID: "first",
                name: "First",
                formattedAddress: "First Address",
                latitude: 52.1,
                longitude: 13.1
            )
        )
        let firstID = try XCTUnwrap(firstPlan.stops.first?.id)
        let secondPlan = try repository.addStop(
            PlaceDetails(
                placeID: "second",
                name: "Second",
                formattedAddress: "Second Address",
                latitude: 52.2,
                longitude: 13.2
            )
        )
        let secondID = try XCTUnwrap(secondPlan.stops.first(where: { $0.placeID == "second" })?.id)
        let thirdPlan = try repository.addStop(
            PlaceDetails(
                placeID: "third",
                name: "Third",
                formattedAddress: "Third Address",
                latitude: 52.3,
                longitude: 13.3
            )
        )
        let thirdID = try XCTUnwrap(thirdPlan.stops.first(where: { $0.placeID == "third" })?.id)

        let reordered = try repository.reorderStops([thirdID, firstID, secondID])
        XCTAssertEqual(reordered.stops.map(\.placeID), ["third", "first", "second"])
        XCTAssertEqual(reordered.stops.map(\.sortIndex), [0, 1, 2])
    }

    func testSwiftDataRepositorySelectsBookmarkedPlanAsCurrent() throws {
        let store = try makeStore()
        let modelContext = store.container.mainContext
        let repository = store.repository

        let currentPlan = try repository.loadCurrentPlan()
        let bookmarkedPlan = Plan(userID: store.userID, title: "Saved Route", isFavorite: true)
        modelContext.insert(bookmarkedPlan)
        modelContext.insert(
            PlanStop(
                planID: bookmarkedPlan.id,
                placeID: "saved-stop",
                name: "Saved Stop",
                formattedAddress: "Saved Stop Address",
                latitude: 52.5,
                longitude: 13.4,
                sortIndex: 0
            )
        )
        try modelContext.save()

        let selected = try repository.selectPlan(id: bookmarkedPlan.id)
        let reloaded = try repository.loadCurrentPlan()

        XCTAssertEqual(selected.id, bookmarkedPlan.id)
        XCTAssertEqual(selected.title, "Saved Route")
        XCTAssertEqual(selected.stops.map(\.placeID), ["saved-stop"])
        XCTAssertEqual(reloaded.id, bookmarkedPlan.id)
        XCTAssertNotEqual(reloaded.id, currentPlan.id)
    }

    func testSwiftDataRepositoryCreatesNewCurrentPlan() throws {
        let store = try makeStore()
        let repository = store.repository
        let originalPlan = try repository.addStop(
            PlaceDetails(
                placeID: "original-stop",
                name: "Original Stop",
                formattedAddress: "Original Stop Address",
                latitude: 52.5,
                longitude: 13.4
            )
        )

        let newPlan = try repository.createNewPlan()
        let currentPlan = try repository.loadCurrentPlan()

        XCTAssertNotEqual(newPlan.id, originalPlan.id)
        XCTAssertEqual(newPlan.title, "Today's Route")
        XCTAssertTrue(newPlan.stops.isEmpty)
        XCTAssertEqual(currentPlan.id, newPlan.id)
    }

    func testSwiftDataRepositoryClaimsLegacyCurrentPlanForSignedInUser() throws {
        let store = try makeStore()
        let modelContext = store.container.mainContext
        let legacyPlan = Plan(title: "Current Plan", isCurrent: true)
        modelContext.insert(legacyPlan)
        modelContext.insert(
            PlanStop(
                planID: legacyPlan.id,
                placeID: "legacy-stop",
                name: "Legacy Stop",
                formattedAddress: "Legacy Stop Address",
                latitude: 52.5,
                longitude: 13.4,
                sortIndex: 0
            )
        )
        try modelContext.save()

        let currentPlan = try store.repository.loadCurrentPlan()

        XCTAssertEqual(currentPlan.id, legacyPlan.id)
        XCTAssertEqual(currentPlan.title, "Today's Route")
        XCTAssertEqual(currentPlan.stops.map(\.placeID), ["legacy-stop"])
        XCTAssertEqual(legacyPlan.userID, store.userID)
    }

    func testSwiftDataRepositoryScopesPlansToUser() throws {
        let store = try makeStore()
        let firstUserRepository = store.repository
        let secondUserID = UUID()
        let secondUserRepository = SwiftDataPlanRepository(
            modelContext: store.container.mainContext,
            userID: secondUserID
        )

        _ = try firstUserRepository.addStop(
            PlaceDetails(
                placeID: "first-user-stop",
                name: "First User Stop",
                formattedAddress: "First User Address",
                latitude: 52.1,
                longitude: 13.1
            )
        )
        _ = try secondUserRepository.addStop(
            PlaceDetails(
                placeID: "second-user-stop",
                name: "Second User Stop",
                formattedAddress: "Second User Address",
                latitude: 52.2,
                longitude: 13.2
            )
        )

        let firstUserPlan = try firstUserRepository.loadCurrentPlan()
        let secondUserPlan = try secondUserRepository.loadCurrentPlan()

        XCTAssertEqual(firstUserPlan.stops.map(\.placeID), ["first-user-stop"])
        XCTAssertEqual(secondUserPlan.stops.map(\.placeID), ["second-user-stop"])
        XCTAssertNotEqual(firstUserPlan.id, secondUserPlan.id)
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

    func testViewModelMovesStopsByDraggedStopID() throws {
        let first = makeStop(placeID: "first", name: "First", sortIndex: 0)
        let second = makeStop(placeID: "second", name: "Second", sortIndex: 1)
        let third = makeStop(placeID: "third", name: "Third", sortIndex: 2)
        let repository = MockPlanRepository(stops: [first, second, third])
        let viewModel = HomeMapViewModel(
            repository: repository,
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService()
        )

        viewModel.load()
        viewModel.moveStop(third.id, to: first.id)

        XCTAssertEqual(viewModel.stops.map(\.placeID), ["third", "first", "second"])
        XCTAssertEqual(viewModel.stops.map(\.sortIndex), [0, 1, 2])
    }

    func testViewModelAppliesShortestRoutePlan() throws {
        let first = makeStop(placeID: "first", name: "First", latitude: 0, longitude: 0, sortIndex: 0)
        let far = makeStop(placeID: "far", name: "Far", latitude: 0, longitude: 10, sortIndex: 1)
        let near = makeStop(placeID: "near", name: "Near", latitude: 0, longitude: 1, sortIndex: 2)
        let repository = MockPlanRepository(stops: [first, far, near])
        let viewModel = HomeMapViewModel(
            repository: repository,
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService()
        )

        viewModel.load()
        viewModel.applyRoutePlan(mode: .shortest, fixedStartStopID: nil, fixedEndStopID: nil)

        XCTAssertEqual(viewModel.stops.map(\.placeID), ["first", "near", "far"])
        XCTAssertEqual(viewModel.stops.map(\.sortIndex), [0, 1, 2])
    }

    func testViewModelSavesRouteNameAndFavoriteState() throws {
        let repository = MockPlanRepository()
        let viewModel = HomeMapViewModel(
            repository: repository,
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService()
        )

        viewModel.load()
        viewModel.saveRouteDetails(title: "House Viewings", isFavorite: true)

        XCTAssertEqual(viewModel.planTitle, "House Viewings")
        XCTAssertTrue(viewModel.isPlanFavorite)
    }

    func testViewModelRefreshesBookmarkedRoutesAfterBookmarkingCurrentRoute() throws {
        let repository = MockPlanRepository()
        let viewModel = HomeMapViewModel(
            repository: repository,
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService()
        )

        viewModel.load()
        XCTAssertTrue(viewModel.bookmarkedPlans.isEmpty)

        viewModel.saveRouteDetails(title: "Weekend Route", isFavorite: true)

        XCTAssertEqual(viewModel.bookmarkedPlans.map(\.title), ["Weekend Route"])
        XCTAssertEqual(viewModel.bookmarkedPlans.first?.id, viewModel.currentPlanID)
    }

    func testViewModelSelectsBookmarkedRouteFromMenu() throws {
        let savedStop = makeStop(placeID: "saved", name: "Saved Stop", sortIndex: 0)
        let bookmarkedPlan = PlanSnapshot(
            id: UUID(),
            title: "Saved Route",
            isFavorite: true,
            stops: [savedStop]
        )
        let repository = MockPlanRepository(bookmarkedPlans: [bookmarkedPlan])
        let viewModel = HomeMapViewModel(
            repository: repository,
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService()
        )

        viewModel.load()
        viewModel.selectBookmarkedPlan(bookmarkedPlan)

        XCTAssertEqual(viewModel.currentPlanID, bookmarkedPlan.id)
        XCTAssertEqual(viewModel.planTitle, "Saved Route")
        XCTAssertEqual(viewModel.stops.map(\.placeID), ["saved"])
    }

    func testViewModelCreatesNewRoute() throws {
        let existingStop = makeStop(placeID: "existing", name: "Existing Stop", sortIndex: 0)
        let repository = MockPlanRepository(stops: [existingStop])
        let viewModel = HomeMapViewModel(
            repository: repository,
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService()
        )

        viewModel.load()
        viewModel.selectedStopID = existingStop.id
        viewModel.createNewRoute()

        XCTAssertEqual(viewModel.planTitle, "Today's Route")
        XCTAssertTrue(viewModel.stops.isEmpty)
        XCTAssertNil(viewModel.selectedStopID)
    }

    func testViewModelStartsAndAdvancesRouteNavigation() throws {
        let first = makeStop(placeID: "first", name: "First", sortIndex: 0)
        let second = makeStop(placeID: "second", name: "Second", sortIndex: 1)
        let third = makeStop(placeID: "third", name: "Third", sortIndex: 2)
        let navigationService = MockRouteNavigationService()
        let viewModel = HomeMapViewModel(
            repository: MockPlanRepository(stops: [first, second, third]),
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService(),
            navigationService: navigationService
        )

        viewModel.load()
        viewModel.startRouteNavigation()

        XCTAssertTrue(viewModel.isNavigatingRoute)
        XCTAssertEqual(viewModel.activeNavigationStopID, first.id)
        XCTAssertEqual(viewModel.selectedStopID, first.id)
        XCTAssertEqual(navigationService.openedStopIDs, [first.id])

        viewModel.advanceRouteNavigation()

        XCTAssertTrue(viewModel.visitedStopIDs.contains(first.id))
        XCTAssertEqual(viewModel.activeNavigationStopID, second.id)
        XCTAssertEqual(navigationService.openedStopIDs, [first.id, second.id])

        viewModel.advanceRouteNavigation()
        viewModel.advanceRouteNavigation()

        XCTAssertFalse(viewModel.isNavigatingRoute)
        XCTAssertNil(viewModel.activeNavigationStopID)
        XCTAssertEqual(viewModel.visitedStopIDs, [first.id, second.id, third.id])
    }

    func testViewModelMarksStopCompletedFromStopActions() throws {
        let stop = makeStop(placeID: "stop", name: "Stop", sortIndex: 0)
        let viewModel = HomeMapViewModel(
            repository: MockPlanRepository(stops: [stop]),
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService()
        )

        viewModel.load()
        viewModel.markStopCompleted(stop)

        XCTAssertEqual(viewModel.visitedStopIDs, [stop.id])

        viewModel.markStopIncomplete(stop)

        XCTAssertTrue(viewModel.visitedStopIDs.isEmpty)
    }

    func testViewModelMarkingStopCompletedNavigatesToNextStop() throws {
        let first = makeStop(placeID: "first", name: "First", sortIndex: 0)
        let second = makeStop(placeID: "second", name: "Second", sortIndex: 1)
        let navigationService = MockRouteNavigationService()
        let viewModel = HomeMapViewModel(
            repository: MockPlanRepository(stops: [first, second]),
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService(),
            navigationService: navigationService
        )

        viewModel.load()
        viewModel.markStopCompleted(first)

        XCTAssertEqual(viewModel.visitedStopIDs, [first.id])
        XCTAssertTrue(viewModel.isNavigatingRoute)
        XCTAssertEqual(viewModel.activeNavigationStopID, second.id)
        XCTAssertEqual(viewModel.selectedStopID, second.id)
        XCTAssertEqual(navigationService.openedStopIDs, [second.id])
    }

    func testViewModelStartNavigationSkipsCompletedStops() throws {
        let first = makeStop(placeID: "first", name: "First", sortIndex: 0)
        let second = makeStop(placeID: "second", name: "Second", sortIndex: 1)
        let navigationService = MockRouteNavigationService()
        let viewModel = HomeMapViewModel(
            repository: MockPlanRepository(stops: [first, second]),
            searchService: MockPlaceSearchService(
                suggestions: [],
                details: PlaceDetails(
                    placeID: "unused",
                    name: "Unused",
                    formattedAddress: "Unused Address",
                    latitude: 0,
                    longitude: 0
                )
            ),
            locationService: MockLocationService(),
            navigationService: navigationService
        )

        viewModel.load()
        viewModel.markStopCompleted(first)
        viewModel.stopRouteNavigation()
        viewModel.startRouteNavigation()

        XCTAssertEqual(viewModel.activeNavigationStopID, second.id)
        XCTAssertEqual(navigationService.openedStopIDs, [second.id, second.id])
    }

    func testRoutePlannerRespectsFixedStartAndEndStops() {
        let first = makeStop(placeID: "first", name: "First", latitude: 0, longitude: 0, sortIndex: 0)
        let far = makeStop(placeID: "far", name: "Far", latitude: 0, longitude: 10, sortIndex: 1)
        let near = makeStop(placeID: "near", name: "Near", latitude: 0, longitude: 1, sortIndex: 2)

        let orderedIDs = RoutePlanner.orderedStopIDs(
            stops: [first, far, near],
            mode: .shortest,
            userCoordinate: nil,
            fixedStartStopID: far.id,
            fixedEndStopID: first.id
        )

        XCTAssertEqual(orderedIDs, [far.id, near.id, first.id])
    }

    func testRoutePlannerFarthestFirstStartsWithFarthestStop() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let near = makeStop(placeID: "near", name: "Near", latitude: 0, longitude: 1, sortIndex: 0)
        let far = makeStop(placeID: "far", name: "Far", latitude: 0, longitude: 10, sortIndex: 1)
        let middle = makeStop(placeID: "middle", name: "Middle", latitude: 0, longitude: 5, sortIndex: 2)

        let orderedIDs = RoutePlanner.orderedStopIDs(
            stops: [near, far, middle],
            mode: .farthestFirst,
            userCoordinate: origin,
            fixedStartStopID: nil,
            fixedEndStopID: nil
        )

        XCTAssertEqual(orderedIDs.first, far.id)
        XCTAssertEqual(orderedIDs, [far.id, middle.id, near.id])
    }

    private func makeStop(placeID: String, name: String, sortIndex: Int) -> PlanStopSnapshot {
        makeStop(
            placeID: placeID,
            name: name,
            latitude: 52 + Double(sortIndex),
            longitude: 13 + Double(sortIndex),
            sortIndex: sortIndex
        )
    }

    private func makeStop(
        placeID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        sortIndex: Int
    ) -> PlanStopSnapshot {
        PlanStopSnapshot(
            id: UUID(),
            placeID: placeID,
            name: name,
            formattedAddress: "\(name) Address",
            latitude: latitude,
            longitude: longitude,
            note: "",
            sortIndex: sortIndex
        )
    }

    private func makeStore() throws -> RepositoryTestStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserAccount.self, Plan.self, PlanStop.self, configurations: configuration)
        let userID = UUID()
        return RepositoryTestStore(
            container: container,
            userID: userID,
            repository: SwiftDataPlanRepository(modelContext: container.mainContext, userID: userID)
        )
    }
}

private struct RepositoryTestStore {
    let container: ModelContainer
    let userID: UUID
    let repository: SwiftDataPlanRepository
}

@MainActor
private final class MockAccountRepository: AccountRepository {
    func loadAccounts() throws -> [UserAccountSnapshot] {
        []
    }

    func account(id: UUID) throws -> UserAccountSnapshot? {
        nil
    }

    func signIn(displayName: String, email: String) throws -> UserAccountSnapshot {
        UserAccountSnapshot(id: UUID(), displayName: displayName, email: email)
    }

    func selectAccount(id: UUID) throws -> UserAccountSnapshot? {
        nil
    }
}

@MainActor
private final class MockPlanRepository: PlanRepository {
    private var plan: PlanSnapshot
    private var savedPlans: [PlanSnapshot]

    init(stops: [PlanStopSnapshot] = [], bookmarkedPlans: [PlanSnapshot] = []) {
        plan = PlanSnapshot(id: UUID(), title: "Today's Route", isFavorite: false, stops: stops)
        savedPlans = bookmarkedPlans
    }

    func loadCurrentPlan() throws -> PlanSnapshot {
        plan
    }

    func loadBookmarkedPlans() throws -> [PlanSnapshot] {
        var bookmarks = savedPlans
        if plan.isFavorite {
            bookmarks.insert(plan, at: 0)
        }
        return bookmarks
    }

    func selectPlan(id: UUID) throws -> PlanSnapshot {
        if plan.id == id {
            return plan
        }
        guard let selectedPlan = savedPlans.first(where: { $0.id == id }) else {
            return plan
        }
        plan = selectedPlan
        return plan
    }

    func createNewPlan() throws -> PlanSnapshot {
        if plan.isFavorite {
            savedPlans.insert(plan, at: 0)
        }
        plan = PlanSnapshot(id: UUID(), title: "Today's Route", isFavorite: false, stops: [])
        return plan
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
            plan = PlanSnapshot(id: plan.id, title: plan.title, isFavorite: plan.isFavorite, stops: plan.stops + [stop])
        }
        return plan
    }

    func updatePlanDetails(title: String, isFavorite: Bool) throws -> PlanSnapshot {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        plan = PlanSnapshot(
            id: plan.id,
            title: trimmedTitle.isEmpty ? "Today's Route" : trimmedTitle,
            isFavorite: isFavorite,
            stops: plan.stops
        )
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
        plan = PlanSnapshot(id: plan.id, title: plan.title, isFavorite: plan.isFavorite, stops: updatedStops)
        return plan
    }

    func removeStop(id: UUID) throws -> PlanSnapshot {
        plan = PlanSnapshot(
            id: plan.id,
            title: plan.title,
            isFavorite: plan.isFavorite,
            stops: plan.stops.filter { $0.id != id }
        )
        return plan
    }

    func moveStops(from source: IndexSet, to destination: Int) throws -> PlanSnapshot {
        let movingStops = source.sorted().map { plan.stops[$0] }
        var remainingStops = plan.stops.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        remainingStops.insert(contentsOf: movingStops, at: adjustedDestination)
        let reindexedStops = remainingStops.enumerated().map { index, stop in
            PlanStopSnapshot(
                id: stop.id,
                placeID: stop.placeID,
                name: stop.name,
                formattedAddress: stop.formattedAddress,
                latitude: stop.latitude,
                longitude: stop.longitude,
                note: stop.note,
                sortIndex: index
            )
        }
        plan = PlanSnapshot(id: plan.id, title: plan.title, isFavorite: plan.isFavorite, stops: reindexedStops)
        return plan
    }

    func reorderStops(_ orderedStopIDs: [UUID]) throws -> PlanSnapshot {
        let stopsByID = Dictionary(uniqueKeysWithValues: plan.stops.map { ($0.id, $0) })
        var seenIDs = Set<UUID>()
        var orderedStops = orderedStopIDs.compactMap { id -> PlanStopSnapshot? in
            guard let stop = stopsByID[id], seenIDs.insert(id).inserted else { return nil }
            return stop
        }
        orderedStops.append(contentsOf: plan.stops.filter { !seenIDs.contains($0.id) })
        let reindexedStops = orderedStops.enumerated().map { index, stop in
            PlanStopSnapshot(
                id: stop.id,
                placeID: stop.placeID,
                name: stop.name,
                formattedAddress: stop.formattedAddress,
                latitude: stop.latitude,
                longitude: stop.longitude,
                note: stop.note,
                sortIndex: index
            )
        }
        plan = PlanSnapshot(id: plan.id, title: plan.title, isFavorite: plan.isFavorite, stops: reindexedStops)
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

@MainActor
private final class MockRouteNavigationService: RouteNavigationService {
    private(set) var openedStopIDs: [UUID] = []

    func openDirections(to stop: PlanStopSnapshot) -> Bool {
        openedStopIDs.append(stop.id)
        return true
    }
}

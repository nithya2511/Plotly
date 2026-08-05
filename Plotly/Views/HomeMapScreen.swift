import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let plotlyDismissKeyboard = Notification.Name("plotlyDismissKeyboard")
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("activeUserID") private var activeUserIDString = ""
    @State private var activeAccount: UserAccountSnapshot?
    @State private var isLoadingAccount = true

    var body: some View {
        Group {
            if isLoadingAccount {
                AccountLoadingView()
            } else if let activeAccount {
                HomeMapScreen(
                    viewModel: HomeMapViewModel(
                        repository: SwiftDataPlanRepository(
                            modelContext: modelContext,
                            userID: activeAccount.id
                        )
                    ),
                    account: activeAccount,
                    onSignOut: signOut
                )
                .id(activeAccount.id)
            } else {
                LoginScreen(
                    viewModel: LoginViewModel(
                        repository: SwiftDataAccountRepository(modelContext: modelContext),
                        onSignedIn: signIn,
                        onSkipped: continueAsGuest
                    )
                )
            }
        }
        .task {
            loadActiveAccount()
        }
    }

    private func loadActiveAccount() {
        defer { isLoadingAccount = false }

        guard let accountID = UUID(uuidString: activeUserIDString) else {
            activeAccount = nil
            activeUserIDString = ""
            return
        }

        if accountID == UserAccountSnapshot.guestID {
            activeAccount = .guest
            return
        }

        do {
            let repository = SwiftDataAccountRepository(modelContext: modelContext)
            activeAccount = try repository.account(id: accountID)
            if activeAccount == nil {
                activeUserIDString = ""
            }
        } catch {
            activeAccount = nil
            activeUserIDString = ""
        }
    }

    private func signIn(_ account: UserAccountSnapshot) {
        activeUserIDString = account.id.uuidString
        activeAccount = account
        isLoadingAccount = false
    }

    private func continueAsGuest(_ account: UserAccountSnapshot) {
        activeUserIDString = account.id.uuidString
        activeAccount = account
        isLoadingAccount = false
    }

    private func signOut() {
        activeUserIDString = ""
        activeAccount = nil
        isLoadingAccount = false
    }
}

private struct AccountLoadingView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Loading account")
        }
    }
}

struct HomeMapScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: HomeMapViewModel
    private let account: UserAccountSnapshot
    private let onSignOut: () -> Void
    @State private var sheetDetent: PlanSheetDetent = .collapsed
    @State private var isMainMenuPresented = false
    @State private var isRoutePlannerPresented = false
    @State private var isRouteEditorPresented = false
    @State private var keyboardHeight: CGFloat = 0

    init(
        viewModel: HomeMapViewModel,
        account: UserAccountSnapshot,
        onSignOut: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.account = account
        self.onSignOut = onSignOut
    }

    var body: some View {
        ZStack(alignment: .top) {
            PlannerMapView(
                stops: viewModel.stops,
                selectedStopID: $viewModel.selectedStopID,
                draftMapPinCoordinate: viewModel.draftMapPinCoordinate,
                userCoordinate: viewModel.userCoordinate,
                visibleInsets: mapVisibleInsets,
                onMapTap: { coordinate in
                    dismissKeyboard()
                    viewModel.stageMapPin(at: coordinate)
                },
                onMapFeatureSelection: { mapFeature in
                    dismissKeyboard()
                    viewModel.stageMapFeature(mapFeature)
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                SearchPanel(
                    viewModel: viewModel,
                    onOpenMenu: {
                        dismissKeyboard()
                        viewModel.refreshBookmarkedPlans()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            isMainMenuPresented = true
                        }
                    }
                )

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage) {
                        viewModel.errorMessage = nil
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if viewModel.draftMapPinCoordinate != nil {
                VStack {
                    HStack {
                        Spacer()
                        DraftMapPinConfirmationControl(
                            onCancel: {
                                dismissKeyboard()
                                viewModel.cancelDraftMapPin()
                            },
                            onConfirm: {
                                dismissKeyboard()
                                viewModel.confirmDraftMapPin()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    sheetDetent = .expanded
                                }
                            }
                        )
                    }
                    Spacer()
                }
                .padding(.top, 74)
                .padding(.trailing, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack {
                Spacer()
                PlanSheet(
                    viewModel: viewModel,
                    detent: $sheetDetent,
                    isKeyboardVisible: keyboardHeight > 0,
                    onEditRoute: {
                        dismissKeyboard()
                        isRouteEditorPresented = true
                    },
                    onPlanRoute: {
                        dismissKeyboard()
                        isRoutePlannerPresented = true
                    }
                )
            }
            .offset(y: -keyboardSheetLift)
            .ignoresSafeArea(edges: .bottom)

            if isMainMenuPresented {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            isMainMenuPresented = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)

                MainMenuDrawer(
                    viewModel: viewModel,
                    account: account,
                    onSignOut: onSignOut,
                    isPresented: $isMainMenuPresented
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isMainMenuPresented)
        .task {
            viewModel.load()
        }
        .onChange(of: viewModel.isAddingStop) { _, isAdding in
            guard isAdding else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                sheetDetent = .expanded
            }
        }
        .onChange(of: viewModel.stops.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                sheetDetent = .expanded
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            viewModel.completeActiveNavigationStopOnReturn()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            updateKeyboardHeight(from: notification)
        }
        .sheet(item: $viewModel.noteEditorStop) { stop in
            NoteEditorSheet(stop: stop, note: $viewModel.noteDraft) {
                viewModel.saveNote()
            }
        }
        .sheet(isPresented: $isRoutePlannerPresented) {
            RoutePlannerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isRouteEditorPresented) {
            RouteEditorSheet(viewModel: viewModel)
        }
    }

    private var mapVisibleInsets: MapVisibleInsets {
        MapVisibleInsets(
            top: 104,
            bottom: visibleSheetHeight + keyboardSheetLift
        )
    }

    private var keyboardSheetLift: CGFloat {
        keyboardHeight
    }

    private var visibleSheetHeight: CGFloat {
        sheetDetent.sheetHeight(
            hasStops: !viewModel.stops.isEmpty,
            isKeyboardVisible: keyboardHeight > 0
        )
    }

    private func dismissKeyboard() {
        NotificationCenter.default.post(name: .plotlyDismissKeyboard, object: nil)
    }

    private func updateKeyboardHeight(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let height = notification.name == UIResponder.keyboardWillHideNotification ? 0 : frame.height
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25

        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = height
        }
    }
}

private enum PlanSheetDetent {
    case collapsed
    case expanded

    func sheetHeight(hasStops: Bool, isKeyboardVisible: Bool = false) -> CGFloat {
        if isKeyboardVisible {
            switch (self, hasStops) {
            case (.collapsed, false):
                return 160
            case (.collapsed, true):
                return 176
            case (.expanded, false):
                return 210
            case (.expanded, true):
                return 292
            }
        }

        switch (self, hasStops) {
        case (.collapsed, false):
            return 190
        case (.collapsed, true):
            return 196
        case (.expanded, false):
            return 260
        case (.expanded, true):
            return 460
        }
    }
}

private struct DraftMapPinConfirmationControl: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(.regularMaterial, in: Circle())
            .accessibilityLabel("Cancel selected map location")

            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.bold))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color(.systemBlue), in: Circle())
            .shadow(color: Color(.systemBlue).opacity(0.28), radius: 12, y: 4)
            .accessibilityLabel("Add selected map location to route")
        }
    }
}

private struct MainMenuDrawer: View {
    @ObservedObject var viewModel: HomeMapViewModel
    let account: UserAccountSnapshot
    let onSignOut: () -> Void
    @Binding var isPresented: Bool

    private func close() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isPresented = false
        }
    }

    var body: some View {
        GeometryReader { proxy in
            NavigationStack {
                List {
                    Section {
                        Button {
                            viewModel.createNewRoute()
                            close()
                        } label: {
                            Label("New route", systemImage: "plus.circle.fill")
                        }
                    }

                    Section("Bookmarked routes") {
                        if viewModel.bookmarkedPlans.isEmpty {
                            ContentUnavailableView(
                                "No Bookmarks",
                                systemImage: "bookmark",
                                description: Text("Bookmarked routes will appear here.")
                            )
                        } else {
                            ForEach(viewModel.bookmarkedPlans) { plan in
                                Button {
                                    viewModel.selectBookmarkedPlan(plan)
                                    close()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(Color(.systemBlue))
                                            .frame(width: 26)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(plan.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text("\(plan.stops.count) \(plan.stops.count == 1 ? "stop" : "stops")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if plan.id == viewModel.currentPlanID {
                                            Text("Current")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section("Account") {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color(.systemBlue))
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Label("Settings", systemImage: "gearshape")
                        Label("Appearance", systemImage: "circle.lefthalf.filled")

                        Button(role: account.isGuest ? nil : .destructive) {
                            close()
                            onSignOut()
                        } label: {
                            Label(
                                account.isGuest ? "Leave guest mode" : "Sign out",
                                systemImage: "rectangle.portrait.and.arrow.right"
                            )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Plotly")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            close()
                        }
                    }
                }
            }
            .frame(width: min(340, proxy.size.width * 0.84))
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(
                UnevenRoundedRectangle(
                    bottomTrailingRadius: 22,
                    topTrailingRadius: 22,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.22), radius: 18, x: 6, y: 0)
            .ignoresSafeArea(edges: .vertical)
        }
    }
}

private struct SearchPanel: View {
    @ObservedObject var viewModel: HomeMapViewModel
    let onOpenMenu: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpenMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.26), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
            .accessibilityLabel("Open menu")

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search places", text: $viewModel.searchText)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .accessibilityIdentifier("place-search-field")

                    if viewModel.isSearching || viewModel.isAddingStop {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.hasSearchText {
                        Button {
                            dismissSearchKeyboard()
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 14)

                if !viewModel.suggestions.isEmpty {
                    Divider()

                    VStack(spacing: 0) {
                        ForEach(viewModel.suggestions.prefix(6)) { suggestion in
                            Button {
                                dismissSearchKeyboard()
                                viewModel.addStop(from: suggestion)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(suggestion.primaryText)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if !suggestion.secondaryText.isEmpty {
                                            Text(suggestion.secondaryText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                    Image(systemName: "plus")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.blue)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)

                            if suggestion.id != viewModel.suggestions.prefix(6).last?.id {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plotlyDismissKeyboard)) { _ in
            dismissSearchKeyboard()
        }
    }

    private func dismissSearchKeyboard() {
        isSearchFocused = false
    }
}

private struct PlanSheet: View {
    @ObservedObject var viewModel: HomeMapViewModel
    @Binding var detent: PlanSheetDetent
    let isKeyboardVisible: Bool
    let onEditRoute: () -> Void
    let onPlanRoute: () -> Void
    @GestureState private var dragOffset: CGFloat = 0
    @State private var draggedStopID: UUID?
    @State private var isEditingRouteTitle = false
    @State private var routeTitleDraft = ""
    @FocusState private var isRouteTitleFocused: Bool

    private var isExpanded: Bool {
        detent == .expanded
    }

    private var collapsedContentHeight: CGFloat {
        PlanSheetDetent.collapsed.sheetHeight(
            hasStops: !viewModel.stops.isEmpty,
            isKeyboardVisible: isKeyboardVisible
        )
    }

    private var expandedContentHeight: CGFloat {
        PlanSheetDetent.expanded.sheetHeight(
            hasStops: !viewModel.stops.isEmpty,
            isKeyboardVisible: isKeyboardVisible
        )
    }

    private var activeHeight: CGFloat {
        isExpanded ? expandedContentHeight : collapsedContentHeight
    }

    private var displayedHeight: CGFloat {
        max(collapsedContentHeight, activeHeight + dragOffset)
    }

    var body: some View {
        VStack(spacing: 14) {
            dragHandle
            sheetHeader
            sheetContent
        }
        .frame(height: displayedHeight, alignment: .top)
        .clipped()
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: -4)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: detent)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.stops.count)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isAddingStop)
        .onChange(of: viewModel.planTitle) { _, newTitle in
            guard !isEditingRouteTitle else { return }
            routeTitleDraft = newTitle
        }
        .onChange(of: isRouteTitleFocused) { _, isFocused in
            if !isFocused, isEditingRouteTitle {
                saveRouteTitle()
            }
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(.secondary.opacity(0.35))
            .frame(width: 42, height: 5)
            .padding(.top, 9)
            .contentShape(Rectangle())
            .onTapGesture {
                clearRouteInteraction()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    detent = isExpanded ? .collapsed : .expanded
                }
            }
            .gesture(sheetDragGesture)
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                let translation = value.translation.height
                if isExpanded {
                    state = min(80, max(-40, translation))
                } else {
                    state = min(40, max(-160, translation))
                }
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if value.translation.height > 36 {
                        detent = .collapsed
                    } else if value.translation.height < -36 {
                        detent = .expanded
                    }
                }
            }
    }

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                if isEditingRouteTitle {
                    TextField("Route name", text: $routeTitleDraft)
                        .font(.headline.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($isRouteTitleFocused)
                        .onSubmit(saveRouteTitle)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel("Route title")
                } else {
                    Button(action: startEditingRouteTitle) {
                        HStack(spacing: 5) {
                            Text(viewModel.planTitle)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit route title")
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onPlanRoute()
            } label: {
                Image(systemName: "wand.and.sparkles")
                    .font(.headline)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.stops.count < 2)
            .accessibilityLabel("Optimize route")

            Button {
                viewModel.toggleRouteFavorite()
            } label: {
                Image(systemName: viewModel.isPlanFavorite ? "bookmark.fill" : "bookmark")
                    .font(.headline)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.isPlanFavorite ? .blue : .secondary)
            .disabled(viewModel.stops.isEmpty)
            .accessibilityLabel(viewModel.isPlanFavorite ? "Remove route bookmark" : "Bookmark route")
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: clearRouteInteraction)
    }

    @ViewBuilder
    private var sheetContent: some View {
        if viewModel.stops.isEmpty {
            EmptyPlanPrompt(isAdding: viewModel.isAddingStop, pendingStopName: viewModel.pendingStopName)
                .padding(.horizontal, 16)
        } else if isExpanded {
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    Color(.systemBackground)
                        .opacity(0.001)
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: clearRouteInteraction)
                        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                            clearRouteInteraction()
                            return true
                        }

                    LazyVStack(spacing: 12) {
                        HStack {
                            if viewModel.routePlanningMode != .manual {
                                RoutePlanStatusBadge(mode: viewModel.routePlanningMode)
                            }

                            Spacer()
                            RouteCountBadge(count: viewModel.stops.count)
                        }

                        if viewModel.isAddingStop {
                            AddingStopRow(name: viewModel.pendingStopName)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.stops.enumerated()), id: \.element.id) { index, stop in
                                StopRow(
                                    stop: stop,
                                    role: RouteStopRole(index: index, total: viewModel.stops.count),
                                    isSelected: viewModel.selectedStopID == stop.id,
                                    isRecentlyAdded: viewModel.recentlyAddedStopID == stop.id,
                                    isPlannedRoute: viewModel.routePlanningMode != .manual,
                                    isVisited: viewModel.visitedStopIDs.contains(stop.id),
                                    isNextNavigationStop: viewModel.nextNavigationStop()?.id == stop.id,
                                    isActiveNavigationStop: viewModel.activeNavigationStopID == stop.id,
                                    showsSeparator: index < viewModel.stops.count - 1,
                                    onSelect: { viewModel.selectedStopID = stop.id },
                                    onGo: { viewModel.goToStop(stop) },
                                    onEditNote: { viewModel.startEditingNote(for: stop) },
                                    onMarkCompleted: { viewModel.markStopCompleted(stop) },
                                    onMarkIncomplete: { viewModel.markStopIncomplete(stop) },
                                    onDelete: { viewModel.remove(stop) }
                                )
                                .onDrag {
                                    draggedStopID = stop.id
                                    return NSItemProvider(object: stop.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: StopReorderDropDelegate(
                                        targetStopID: stop.id,
                                        draggedStopID: $draggedStopID,
                                        moveAction: { draggedID, targetID in
                                            viewModel.moveStop(draggedID, to: targetID)
                                        }
                                    )
                                )
                            }
                        }
                        .background(Color(.secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
            }
            .contentShape(Rectangle())
            .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                clearRouteInteraction()
                return true
            }
            .frame(maxHeight: .infinity)
        } else {
            let nextStop = viewModel.nextNavigationStop()
            let previewStop = nextStop ?? viewModel.stops.last ?? viewModel.stops[0]
            CompactStopPreview(
                stop: previewStop,
                count: viewModel.stops.count,
                isAdding: viewModel.isAddingStop,
                isNextStop: nextStop != nil,
                pendingStopName: viewModel.pendingStopName,
                onGo: { viewModel.goToStop(previewStop) },
                onExpand: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        detent = .expanded
                    }
                }
            )
            .padding(.horizontal, 16)
        }
    }

    private var statusText: String {
        if let pendingStopName = viewModel.pendingStopName {
            return "Adding \(pendingStopName)"
        }

        switch viewModel.stops.count {
        case 0:
            return "Search above to build your route"
        case 1:
            return "Saved stop"
        default:
            return "Saved in visit order"
        }
    }

    private func clearRouteInteraction() {
        draggedStopID = nil
        viewModel.selectedStopID = nil
    }

    private func startEditingRouteTitle() {
        clearRouteInteraction()
        routeTitleDraft = viewModel.planTitle
        isEditingRouteTitle = true
        DispatchQueue.main.async {
            isRouteTitleFocused = true
        }
    }

    private func saveRouteTitle() {
        let title = routeTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingRouteTitle = false
        isRouteTitleFocused = false
        viewModel.saveRouteDetails(title: title, isFavorite: viewModel.isPlanFavorite)
    }
}

private struct StopReorderDropDelegate: DropDelegate {
    let targetStopID: UUID
    @Binding var draggedStopID: UUID?
    let moveAction: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedStopID, draggedStopID != targetStopID else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            moveAction(draggedStopID, targetStopID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedStopID = nil
        return true
    }
}

private struct RouteCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) \(count == 1 ? "stop" : "stops")")
            .font(.caption2.weight(.bold))
            .foregroundStyle(count == 0 ? Color.secondary : Color.blue)
            .frame(minHeight: 20)
            .padding(.horizontal, 8)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .accessibilityLabel("\(count) stops")
    }
}

private struct RoutePlanStatusBadge: View {
    let mode: RoutePlanningMode

    var body: some View {
        Label(mode == .shortest ? "Optimized" : mode.title, systemImage: "sparkles")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(.systemBlue))
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .background(Color(.systemBlue).opacity(0.1), in: Capsule())
    }
}

private struct RouteNavigationControl: View {
    @ObservedObject var viewModel: HomeMapViewModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                Image(systemName: viewModel.isNavigatingRoute ? "location.north.line.fill" : "location.north.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if viewModel.isNavigatingRoute {
                Button {
                    viewModel.stopRouteNavigation()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white)
                .accessibilityLabel("Stop navigation")

                Button {
                    viewModel.advanceRouteNavigation()
                } label: {
                    Label(nextButtonTitle, systemImage: isFinalStop ? "checkmark" : "arrow.forward")
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(.systemBlue))
                .controlSize(.small)
            } else {
                Button {
                    viewModel.startRouteNavigation()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(.systemBlue))
                .controlSize(.small)
                .disabled(viewModel.nextNavigationStop() == nil)
                .accessibilityLabel("Start navigating")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(navigationBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color(.systemBlue).opacity(viewModel.nextNavigationStop() == nil ? 0 : 0.22), radius: 12, y: 4)
    }

    private var activeStop: PlanStopSnapshot? {
        guard let activeNavigationStopID = viewModel.activeNavigationStopID else { return nil }
        return viewModel.stops.first(where: { $0.id == activeNavigationStopID })
    }

    private var activeStopIndex: Int? {
        guard let activeNavigationStopID = viewModel.activeNavigationStopID else { return nil }
        return viewModel.stops.firstIndex(where: { $0.id == activeNavigationStopID })
    }

    private var isFinalStop: Bool {
        guard let activeStopIndex else { return false }
        return activeStopIndex == viewModel.stops.indices.last
    }

    private var title: String {
        if viewModel.isNavigatingRoute, let activeStop {
            return "Navigating to \(activeStop.name)"
        }

        if let nextStop = viewModel.nextNavigationStop() {
            return "Start from \(nextStop.name)"
        }

        return "Route complete"
    }

    private var subtitle: String {
        if viewModel.isNavigatingRoute {
            return "\(viewModel.visitedStopIDs.count) visited"
        }

        if viewModel.nextNavigationStop() == nil {
            return "\(viewModel.visitedStopIDs.count) completed"
        }

        return "Apple Maps will use your current location"
    }

    private var nextButtonTitle: String {
        isFinalStop ? "Finish" : "Next"
    }

    private var navigationBackground: Color {
        viewModel.nextNavigationStop() == nil ? Color(.tertiaryLabel) : Color(.systemBlue)
    }
}

private enum RouteStopRole {
    case single
    case start
    case waypoint
    case destination

    init(index: Int, total: Int) {
        if total <= 1 {
            self = .single
        } else if index == 0 {
            self = .start
        } else if index == total - 1 {
            self = .destination
        } else {
            self = .waypoint
        }
    }

    var label: String {
        switch self {
        case .single:
            return "Stop"
        case .start:
            return "Start"
        case .waypoint:
            return "Waypoint"
        case .destination:
            return "Stop"
        }
    }

    var systemImage: String {
        switch self {
        case .single, .destination:
            return "mappin"
        case .start:
            return "location.fill"
        case .waypoint:
            return "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .start:
            return Color(.systemTeal)
        case .single, .destination:
            return Color(.systemRed).opacity(0.82)
        case .waypoint:
            return Color(.tertiaryLabel)
        }
    }

    var showsTopConnector: Bool {
        switch self {
        case .single, .start:
            return false
        case .waypoint, .destination:
            return true
        }
    }

    var showsBottomConnector: Bool {
        switch self {
        case .single, .destination:
            return false
        case .start, .waypoint:
            return true
        }
    }
}

private struct StopRow: View {
    let stop: PlanStopSnapshot
    let role: RouteStopRole
    let isSelected: Bool
    let isRecentlyAdded: Bool
    let isPlannedRoute: Bool
    let isVisited: Bool
    let isNextNavigationStop: Bool
    let isActiveNavigationStop: Bool
    let showsSeparator: Bool
    let onSelect: () -> Void
    let onGo: () -> Void
    let onEditNote: () -> Void
    let onMarkCompleted: () -> Void
    let onMarkIncomplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RouteStopIndicator(
                role: role,
                isSelected: isSelected,
                isPlannedRoute: isPlannedRoute,
                isVisited: isVisited,
                isActiveNavigationStop: isActiveNavigationStop
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(roleText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(roleLabelColor)
                    .textCase(.uppercase)
                Text(stop.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isVisited ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(stop.formattedAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !stop.note.isEmpty {
                    Text(stop.note)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if isNextNavigationStop {
                    Button(action: onGo) {
                        Label("Go", systemImage: "location.north.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Go to \(stop.name)")
                }

                Menu {
                    Section("Navigation") {
                        Button(isVisited ? "Go again" : "Go to stop", systemImage: "location.north.line", action: onGo)
                    }

                    Section("Progress") {
                        if isVisited {
                            Button("Mark as yet to travel", systemImage: "circle", action: onMarkIncomplete)
                        } else {
                            Button("Mark as traversed", systemImage: "checkmark.circle", action: onMarkCompleted)
                        }
                    }

                    Section {
                        Button("Edit note", systemImage: "note.text", action: onEditNote)
                        Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Stop actions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            if isSelected || isActiveNavigationStop {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(.systemBlue).opacity(isActiveNavigationStop ? 0.7 : 0.34))
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
        }
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Divider()
                    .padding(.leading, 58)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityIdentifier("plan-stop-row")
        .accessibilityAddTraits(.isButton)
    }

    private var roleText: String {
        if isActiveNavigationStop {
            return "In Maps"
        }

        if isVisited {
            return "Traversed"
        }

        if isNextNavigationStop {
            return "Next to travel"
        }

        if isRecentlyAdded {
            return "Added"
        }

        return role.label
    }

    private var roleLabelColor: Color {
        if isVisited {
            return Color(.secondaryLabel)
        }

        if isActiveNavigationStop {
            return Color(.systemBlue)
        }

        return isSelected ? Color(.secondaryLabel) : role.color
    }
}

private struct RouteStopIndicator: View {
    let role: RouteStopRole
    let isSelected: Bool
    let isPlannedRoute: Bool
    let isVisited: Bool
    let isActiveNavigationStop: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(connectorColor(role.showsTopConnector))
                .frame(width: isPlannedRoute ? 3 : 2, height: 10)

            ZStack {
                Circle()
                    .fill(markerFill)
                    .frame(width: isPlannedRoute ? 32 : 30, height: isPlannedRoute ? 32 : 30)

                if role == .waypoint {
                    if isVisited {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(markerColor)
                    } else {
                        Circle()
                            .fill(markerColor)
                            .frame(width: isPlannedRoute ? 10 : 8, height: isPlannedRoute ? 10 : 8)
                    }
                } else {
                    Image(systemName: isVisited ? "checkmark" : role.systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(markerColor)
                }
            }
            .overlay {
                if isPlannedRoute || isActiveNavigationStop {
                    Circle()
                        .strokeBorder(Color(.systemBlue).opacity(isSelected || isActiveNavigationStop ? 0.46 : 0.28), lineWidth: 1)
                }
            }

            Rectangle()
                .fill(connectorColor(role.showsBottomConnector))
                .frame(width: isPlannedRoute ? 3 : 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 34)
        .frame(minHeight: 58)
        .padding(.top, -10)
    }

    private var markerColor: Color {
        if isVisited {
            return Color(.systemGreen)
        }

        if isPlannedRoute || isActiveNavigationStop {
            return Color(.systemBlue)
        }

        return role.color
    }

    private var markerFill: Color {
        markerColor.opacity(isSelected ? 0.16 : (isPlannedRoute ? 0.12 : 0.08))
    }

    private func connectorColor(_ isVisible: Bool) -> Color {
        guard isVisible else { return .clear }
        return isPlannedRoute ? Color(.systemBlue).opacity(0.38) : Color.secondary.opacity(0.28)
    }
}

private struct EmptyPlanPrompt: View {
    let isAdding: Bool
    let pendingStopName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isAdding {
                AddingStopRow(name: pendingStopName)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start with a place search")
                            .font(.subheadline.weight(.semibold))
                        Text("Added locations will appear here as stops, with markers on the map.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(13)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct AddingStopRow: View {
    let name: String?

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("Adding stop")
                    .font(.subheadline.weight(.semibold))
                Text(name ?? "Fetching place details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(13)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CompactStopPreview: View {
    let stop: PlanStopSnapshot
    let count: Int
    let isAdding: Bool
    let isNextStop: Bool
    let pendingStopName: String?
    let onGo: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onExpand) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.14))
                        Image(systemName: isAdding ? "clock" : "location.north.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(labelText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(isAdding ? (pendingStopName ?? "Adding stop") : stop.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(count == 1 ? "View" : "View all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            .buttonStyle(.plain)

            if isNextStop {
                Button(action: onGo) {
                    Label("Go", systemImage: "location.north.fill")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.bold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Go to \(stop.name)")
            }
        }
        .padding(13)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var labelText: String {
        if isAdding {
            return "Updating route list"
        }

        return isNextStop ? "Next to travel" : "Route complete"
    }
}

private struct RoutePlannerSheet: View {
    @ObservedObject var viewModel: HomeMapViewModel
    @State private var mode: RoutePlanningMode = .shortest
    @State private var fixedStartStopID: UUID?
    @State private var fixedEndStopID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Optimize by", selection: $mode) {
                        ForEach(RoutePlanningMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Start") {
                    StopPickerRow(
                        title: "Starting point",
                        placeholder: defaultStartTitle,
                        stops: viewModel.stops,
                        selection: $fixedStartStopID
                    )
                }

                Section("End") {
                    StopPickerRow(
                        title: "Final stop",
                        placeholder: "No fixed end",
                        stops: viewModel.stops.filter { $0.id != fixedStartStopID },
                        selection: $fixedEndStopID
                    )
                }
            }
            .navigationTitle("Plan Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.applyRoutePlan(
                            mode: mode,
                            fixedStartStopID: fixedStartStopID,
                            fixedEndStopID: fixedEndStopID
                        )
                        dismiss()
                    }
                    .disabled(viewModel.stops.count < 2)
                }
            }
            .onChange(of: fixedStartStopID) { _, newValue in
                if fixedEndStopID == newValue {
                    fixedEndStopID = nil
                }
            }
        }
    }

    private var defaultStartTitle: String {
        viewModel.userCoordinate == nil ? "First stop" : "Current location"
    }
}

private struct RouteEditorSheet: View {
    @ObservedObject var viewModel: HomeMapViewModel
    @State private var routeName: String
    @State private var isFavorite: Bool
    @Environment(\.dismiss) private var dismiss

    init(viewModel: HomeMapViewModel) {
        self.viewModel = viewModel
        _routeName = State(initialValue: viewModel.planTitle)
        _isFavorite = State(initialValue: viewModel.isPlanFavorite)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Route name", text: $routeName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("route-name-field")

                    Toggle(isOn: $isFavorite) {
                        Label("Bookmarked", systemImage: isFavorite ? "bookmark.fill" : "bookmark")
                    }
                }

                Section {
                    HStack {
                        Text("Stops")
                        Spacer()
                        Text("\(viewModel.stops.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveRouteDetails(title: routeName, isFavorite: isFavorite)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct StopPickerRow: View {
    let title: String
    let placeholder: String
    let stops: [PlanStopSnapshot]
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text(placeholder).tag(UUID?.none)
            ForEach(stops) { stop in
                Text(stop.name).tag(UUID?.some(stop.id))
            }
        }
    }
}

private struct NoteEditorSheet: View {
    let stop: PlanStopSnapshot
    @Binding var note: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.name)
                        .font(.headline)
                    Text(stop.formattedAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $note)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("stop-note-editor")

                Spacer()
            }
            .padding()
            .navigationTitle("Stop note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UserAccount.self, Plan.self, PlanStop.self], inMemory: true)
}

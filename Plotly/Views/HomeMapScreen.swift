import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HomeMapScreen(
            viewModel: HomeMapViewModel(
                repository: SwiftDataPlanRepository(modelContext: modelContext)
            )
        )
    }
}

struct HomeMapScreen: View {
    @StateObject private var viewModel: HomeMapViewModel
    @State private var sheetDetent: PlanSheetDetent = .collapsed

    init(viewModel: HomeMapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            PlannerMapView(
                stops: viewModel.stops,
                selectedStopID: $viewModel.selectedStopID,
                userCoordinate: viewModel.userCoordinate
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                SearchPanel(viewModel: viewModel)

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage) {
                        viewModel.errorMessage = nil
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            VStack {
                Spacer()
                PlanSheet(viewModel: viewModel, detent: $sheetDetent)
            }
            .ignoresSafeArea(edges: .bottom)
        }
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
        .sheet(item: $viewModel.noteEditorStop) { stop in
            NoteEditorSheet(stop: stop, note: $viewModel.noteDraft) {
                viewModel.saveNote()
            }
        }
    }
}

private enum PlanSheetDetent {
    case collapsed
    case expanded
}

private struct SearchPanel: View {
    @ObservedObject var viewModel: HomeMapViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search places", text: $viewModel.searchText)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .accessibilityIdentifier("place-search-field")

                if viewModel.isSearching || viewModel.isAddingStop {
                    ProgressView()
                        .controlSize(.small)
                } else if viewModel.hasSearchText {
                    Button {
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
}

private struct PlanSheet: View {
    @ObservedObject var viewModel: HomeMapViewModel
    @Binding var detent: PlanSheetDetent
    @GestureState private var dragOffset: CGFloat = 0

    private var isExpanded: Bool {
        detent == .expanded
    }

    private var collapsedContentHeight: CGFloat {
        viewModel.stops.isEmpty ? 190 : 178
    }

    private var expandedContentHeight: CGFloat {
        viewModel.stops.isEmpty ? 260 : 430
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
        .padding(.bottom, 16)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: -4)
        .gesture(
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
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: detent)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.stops.count)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isAddingStop)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(.secondary.opacity(0.35))
            .frame(width: 42, height: 5)
            .padding(.top, 9)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    detent = isExpanded ? .collapsed : .expanded
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

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.planTitle)
                    .font(.headline.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(viewModel.stops.count)")
                .font(.headline.weight(.bold))
                .foregroundStyle(viewModel.stops.isEmpty ? Color.secondary : Color.blue)
                .frame(width: 34, height: 34)
                .background(Color(.secondarySystemBackground), in: Circle())
                .accessibilityLabel("\(viewModel.stops.count) stops")

            Button {
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .font(.headline)
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityLabel("Route optimization coming later")
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var sheetContent: some View {
        if viewModel.stops.isEmpty {
            EmptyPlanPrompt(isAdding: viewModel.isAddingStop, pendingStopName: viewModel.pendingStopName)
                .padding(.horizontal, 16)
        } else if isExpanded {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.isAddingStop {
                        AddingStopRow(name: viewModel.pendingStopName)
                    }

                    ForEach(Array(viewModel.stops.enumerated()), id: \.element.id) { index, stop in
                        StopRow(
                            stop: stop,
                            role: RouteStopRole(index: index, total: viewModel.stops.count),
                            isSelected: viewModel.selectedStopID == stop.id,
                            isRecentlyAdded: viewModel.recentlyAddedStopID == stop.id,
                            onSelect: { viewModel.selectedStopID = stop.id },
                            onEditNote: { viewModel.startEditingNote(for: stop) },
                            onDelete: { viewModel.remove(stop) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .frame(maxHeight: 300)
        } else {
            CompactStopPreview(
                stop: viewModel.stops.last ?? viewModel.stops[0],
                count: viewModel.stops.count,
                isAdding: viewModel.isAddingStop,
                pendingStopName: viewModel.pendingStopName,
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
            return "1 stop saved"
        default:
            return "\(viewModel.stops.count) stops saved in visit order"
        }
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
            return .green
        case .single, .destination:
            return .red
        case .waypoint:
            return .secondary
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
    let onSelect: () -> Void
    let onEditNote: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                RouteStopIndicator(role: role, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(role.color)
                        .textCase(.uppercase)
                    Text(stop.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
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

                Menu {
                    Button("Edit note", systemImage: "note.text", action: onEditNote)
                    Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .overlay(alignment: .topTrailing) {
                if isRecentlyAdded {
                    Text("Added")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.12), in: Capsule())
                        .padding(8)
                }
            }
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan-stop-row")
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.blue.opacity(0.1)
        }

        if isRecentlyAdded {
            return Color.green.opacity(0.1)
        }

        return Color(.secondarySystemBackground)
    }
}

private struct RouteStopIndicator: View {
    let role: RouteStopRole
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(role.showsTopConnector ? Color.secondary.opacity(0.28) : Color.clear)
                .frame(width: 2, height: 10)

            ZStack {
                Circle()
                    .fill(role.color.opacity(isSelected ? 0.18 : 0.1))
                    .frame(width: 30, height: 30)

                if role == .waypoint {
                    Circle()
                        .fill(role.color)
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: role.systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(role.color)
                }
            }

            Rectangle()
                .fill(role.showsBottomConnector ? Color.secondary.opacity(0.28) : Color.clear)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 34)
        .frame(minHeight: 58)
        .padding(.top, -10)
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
    let pendingStopName: String?
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.14))
                    Image(systemName: isAdding ? "clock" : "mappin.and.ellipse")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isAdding ? "Updating route list" : "Latest stop")
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
            .padding(13)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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
                .lineLimit(2)
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Plan.self, PlanStop.self], inMemory: true)
}

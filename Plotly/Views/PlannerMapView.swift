import CoreLocation
import MapKit
import SwiftUI

struct PlannerMapView: View {
    let stops: [PlanStopSnapshot]
    @Binding var selectedStopID: UUID?
    let draftMapPinCoordinate: CLLocationCoordinate2D?
    let userCoordinate: CLLocationCoordinate2D?
    let visibleInsets: MapVisibleInsets
    let mapFocusRequest: MapStopFocusRequest?
    let routeOverviewRequest: UUID?
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onMapFeatureSelection: (MapFeature) -> Void

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 0, proxy.size.height > 0 {
                activeMap(size: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                Color(.systemBackground)
            }
        }
    }

    @ViewBuilder
    private func activeMap(size: CGSize) -> some View {
        MapKitPlannerMapView(
            stops: stops,
            selectedStopID: $selectedStopID,
            draftMapPinCoordinate: draftMapPinCoordinate,
            userCoordinate: userCoordinate,
            visibleInsets: visibleInsets,
            mapSize: size,
            mapFocusRequest: mapFocusRequest,
            routeOverviewRequest: routeOverviewRequest,
            onMapTap: onMapTap,
            onMapFeatureSelection: onMapFeatureSelection
        )
    }
}

struct MapVisibleInsets: Equatable {
    let top: CGFloat
    let bottom: CGFloat
}

private struct MapKitPlannerMapView: View {
    let stops: [PlanStopSnapshot]
    @Binding var selectedStopID: UUID?
    let draftMapPinCoordinate: CLLocationCoordinate2D?
    let userCoordinate: CLLocationCoordinate2D?
    let visibleInsets: MapVisibleInsets
    let mapSize: CGSize
    let mapFocusRequest: MapStopFocusRequest?
    let routeOverviewRequest: UUID?
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onMapFeatureSelection: (MapFeature) -> Void
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedMapFeature: MapFeature?
    @State private var lastAppliedCameraRegion: ComparableMapRegion?

    private var routeCoordinates: [CLLocationCoordinate2D] {
        stops.map(\.coordinate)
    }

    private var focusedRegion: MKCoordinateRegion {
        if let draftMapPinCoordinate {
            return visibleCenterRegion(
                center: draftMapPinCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
            )
        }

        if let selected = stops.first(where: { $0.id == selectedStopID }) {
            return visibleCenterRegion(
                center: selected.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        }

        if let first = stops.first {
            return visibleCenterRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        if let userCoordinate {
            return visibleCenterRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        return visibleCenterRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
    }

    private var focusedCameraPosition: MapCameraPosition {
        if draftMapPinCoordinate != nil || stops.count <= 1 {
            return .region(focusedRegion)
        }

        return .region(routeOverviewRegion)
    }

    private var draftMapPinFocusKey: DraftMapPinFocusKey? {
        guard let draftMapPinCoordinate else { return nil }
        return DraftMapPinFocusKey(
            latitude: draftMapPinCoordinate.latitude,
            longitude: draftMapPinCoordinate.longitude
        )
    }

    private var routeOverviewRegion: MKCoordinateRegion {
        let coordinates = stops.map(\.coordinate)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? 0
        let maxLatitude = latitudes.max() ?? 0
        let minLongitude = longitudes.min() ?? 0
        let maxLongitude = longitudes.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = maxLatitude - minLatitude
        let longitudeDelta = maxLongitude - minLongitude
        let verticalVisibleFraction = visibleMapHeightFraction
        let span = MKCoordinateSpan(
            latitudeDelta: max((latitudeDelta * 2.35) / verticalVisibleFraction, 0.035),
            longitudeDelta: max(longitudeDelta * 2.45, 0.035)
        )

        return visibleCenterRegion(center: center, span: span)
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $selectedMapFeature) {
                if userCoordinate != nil {
                    UserAnnotation()
                }

                if routeCoordinates.count > 1 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(
                            Color(.systemBlue).opacity(0.62),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }

                ForEach(stops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        Button {
                            selectedStopID = stop.id
                        } label: {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(selectedStopID == stop.id ? .blue : .red, .white)
                                .shadow(radius: 3)
                        }
                        .accessibilityLabel(stop.name)
                    }
                }

                if let draftMapPinCoordinate {
                    Annotation("Selected location", coordinate: draftMapPinCoordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.orange, .white)
                            .shadow(radius: 4)
                            .accessibilityLabel("Selected map location")
                    }
                }
            }
            .simultaneousGesture(mapLongPressGesture(proxy: proxy))
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        dismissKeyboardForMapTap(at: coordinate)
                    }
            )
        }
        .onAppear(perform: focusMap)
        .onChange(of: stops.map(\.id)) { _, _ in
            focusMap()
        }
        .onChange(of: selectedStopID) { _, stopID in
            if draftMapPinCoordinate != nil {
                focusMap()
            } else if let stopID {
                focusMap(on: stopID)
            } else {
                focusMap()
            }
        }
        .onChange(of: draftMapPinFocusKey) { _, _ in
            focusMap()
        }
        .onChange(of: visibleInsets) { _, _ in
            if draftMapPinCoordinate != nil || selectedStopID != nil {
                focusMap()
            }
        }
        .onChange(of: mapFocusRequest) { _, request in
            guard let request else { return }
            focusMap(on: request.stopID)
        }
        .onChange(of: routeOverviewRequest) { _, request in
            guard request != nil else { return }
            focusMap()
        }
        .onChange(of: selectedMapFeature) { _, feature in
            guard let feature else { return }
            onMapFeatureSelection(feature)
            selectedMapFeature = nil
        }
        .mapFeatureSelectionAccessory(nil)
    }

    private func focusMap() {
        applyCameraPosition(focusedCameraPosition)
    }

    private func focusMap(on stopID: UUID) {
        guard let stop = stops.first(where: { $0.id == stopID }) else {
            focusMap()
            return
        }

        applyCameraPosition(
            .region(
                visibleCenterRegion(
                    center: stop.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                )
            )
        )
    }

    private func applyCameraPosition(_ position: MapCameraPosition) {
        if let region = position.region {
            let comparableRegion = ComparableMapRegion(region)
            guard comparableRegion != lastAppliedCameraRegion else { return }
            lastAppliedCameraRegion = comparableRegion
        } else {
            lastAppliedCameraRegion = nil
        }

        withAnimation(.easeInOut(duration: 0.28)) {
            cameraPosition = position
        }
    }

    private func dismissKeyboardForMapTap(at coordinate: CLLocationCoordinate2D) {
        NotificationCenter.default.post(name: .plotlyDismissKeyboard, object: nil)
    }

    private func mapLongPressGesture(proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.55, maximumDistance: 12)
            .simultaneously(with: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard value.first == true, let location = value.second?.location else { return }
                guard let coordinate = proxy.convert(location, from: .local) else { return }
                onMapTap(coordinate)
            }
    }

    private func visibleCenterRegion(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan
    ) -> MKCoordinateRegion {
        let verticalOffset = visibleCenterLatitudeOffset(for: span.latitudeDelta)
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: center.latitude - verticalOffset,
            longitude: center.longitude
        )

        return MKCoordinateRegion(center: adjustedCenter, span: span)
    }

    private func visibleCenterLatitudeOffset(for latitudeDelta: CLLocationDegrees) -> CLLocationDegrees {
        let height = max(mapSize.height, 1)
        let topInset = clampedInset(visibleInsets.top, maxValue: height * 0.45)
        let bottomInset = clampedInset(visibleInsets.bottom, maxValue: height * 0.72)
        return latitudeDelta * CLLocationDegrees((bottomInset - topInset) / (2 * height))
    }

    private var visibleMapHeightFraction: CGFloat {
        let height = max(mapSize.height, 1)
        let topInset = clampedInset(visibleInsets.top, maxValue: height * 0.45)
        let bottomInset = clampedInset(visibleInsets.bottom, maxValue: height * 0.72)
        return max((height - topInset - bottomInset) / height, 0.18)
    }

    private func clampedInset(_ value: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(max(value, 0), maxValue)
    }
}

private struct DraftMapPinFocusKey: Equatable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
}

private struct ComparableMapRegion: Equatable {
    let latitude: Int
    let longitude: Int
    let latitudeDelta: Int
    let longitudeDelta: Int

    init(_ region: MKCoordinateRegion) {
        latitude = Self.scaled(region.center.latitude)
        longitude = Self.scaled(region.center.longitude)
        latitudeDelta = Self.scaled(region.span.latitudeDelta)
        longitudeDelta = Self.scaled(region.span.longitudeDelta)
    }

    private static func scaled(_ value: CLLocationDegrees) -> Int {
        Int((value * 1_000_000).rounded())
    }
}

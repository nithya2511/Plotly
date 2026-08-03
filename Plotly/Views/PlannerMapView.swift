import CoreLocation
import MapKit
import SwiftUI

struct PlannerMapView: View {
    let stops: [PlanStopSnapshot]
    @Binding var selectedStopID: UUID?
    let userCoordinate: CLLocationCoordinate2D?

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 0, proxy.size.height > 0 {
                activeMap
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                Color(.systemBackground)
            }
        }
    }

    @ViewBuilder
    private var activeMap: some View {
        MapKitPlannerMapView(
            stops: stops,
            selectedStopID: $selectedStopID,
            userCoordinate: userCoordinate
        )
    }
}

private struct MapKitPlannerMapView: View {
    let stops: [PlanStopSnapshot]
    @Binding var selectedStopID: UUID?
    let userCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var routeCoordinates: [CLLocationCoordinate2D] {
        stops.map(\.coordinate)
    }

    private var focusedRegion: MKCoordinateRegion {
        if let selected = stops.first(where: { $0.id == selectedStopID }) {
            return MKCoordinateRegion(
                center: selected.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        }

        if let first = stops.first {
            return MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        if let userCoordinate {
            return MKCoordinateRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
    }

    private var focusedCameraPosition: MapCameraPosition {
        if selectedStopID != nil || stops.count <= 1 {
            return .region(focusedRegion)
        }

        return .rect(routeMapRect)
    }

    private var routeMapRect: MKMapRect {
        let points = stops.map { MKMapPoint($0.coordinate) }
        let rect = points.dropFirst().reduce(
            MKMapRect(origin: points[0], size: MKMapSize(width: 1, height: 1))
        ) { partialResult, point in
            partialResult.union(MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1)))
        }

        let inset = max(rect.width, rect.height) * 0.22
        return rect.insetBy(dx: -max(inset, 1600), dy: -max(inset, 1600))
    }

    var body: some View {
        Map(position: $cameraPosition) {
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
        }
        .onAppear(perform: focusMap)
        .onChange(of: stops.map(\.id)) { _, _ in
            focusMap()
        }
        .onChange(of: selectedStopID) { _, _ in
            focusMap()
        }
        .mapControls {
            if userCoordinate != nil {
                MapUserLocationButton()
            }
            MapCompass()
        }
    }

    private func focusMap() {
        withAnimation(.easeInOut(duration: 0.28)) {
            cameraPosition = focusedCameraPosition
        }
    }
}

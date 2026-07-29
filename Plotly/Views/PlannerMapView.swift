import CoreLocation
import MapKit
import SwiftUI

#if canImport(GoogleMaps)
import GoogleMaps
#endif

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
        #if canImport(GoogleMaps)
            if GoogleSDKBootstrap.isConfigured {
                GooglePlannerMapView(
                    stops: stops,
                    selectedStopID: $selectedStopID,
                    userCoordinate: userCoordinate
                )
            } else {
                MapKitPlannerMapView(
                    stops: stops,
                    selectedStopID: $selectedStopID,
                    userCoordinate: userCoordinate
                )
            }
        #else
            MapKitPlannerMapView(
                stops: stops,
                selectedStopID: $selectedStopID,
                userCoordinate: userCoordinate
            )
        #endif
    }
}

private struct MapKitPlannerMapView: View {
    let stops: [PlanStopSnapshot]
    @Binding var selectedStopID: UUID?
    let userCoordinate: CLLocationCoordinate2D?

    private var initialRegion: MKCoordinateRegion {
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

    var body: some View {
        Map(initialPosition: .region(initialRegion)) {
            if userCoordinate != nil {
                UserAnnotation()
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
        .mapControls {
            if userCoordinate != nil {
                MapUserLocationButton()
            }
            MapCompass()
        }
    }
}

#if canImport(GoogleMaps)
private struct GooglePlannerMapView: UIViewRepresentable {
    let stops: [PlanStopSnapshot]
    @Binding var selectedStopID: UUID?
    let userCoordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(
            withLatitude: userCoordinate?.latitude ?? 37.7749,
            longitude: userCoordinate?.longitude ?? -122.4194,
            zoom: userCoordinate == nil ? 11 : 13
        )
        let initialFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let mapView = GMSMapView.map(withFrame: initialFrame, camera: camera)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = userCoordinate != nil
        mapView.settings.myLocationButton = true
        mapView.padding = UIEdgeInsets(top: 74, left: 0, bottom: 220, right: 0)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        mapView.clear()
        mapView.isMyLocationEnabled = userCoordinate != nil
        mapView.padding = UIEdgeInsets(top: 74, left: 0, bottom: stops.isEmpty ? 190 : 300, right: 0)

        for stop in stops {
            let marker = GMSMarker(position: stop.coordinate)
            marker.title = stop.name
            marker.snippet = stop.formattedAddress
            marker.userData = stop.id.uuidString
            marker.icon = GMSMarker.markerImage(with: selectedStopID == stop.id ? .systemBlue : .systemRed)
            marker.map = mapView
        }

        if let selected = stops.first(where: { $0.id == selectedStopID }) {
            mapView.animate(toLocation: selected.coordinate)
            mapView.animate(toZoom: max(mapView.camera.zoom, 14))
        } else if stops.count > 1 {
            var bounds = GMSCoordinateBounds(coordinate: stops[0].coordinate, coordinate: stops[1].coordinate)
            for stop in stops.dropFirst(2) {
                bounds = bounds.includingCoordinate(stop.coordinate)
            }
            mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 80))
        } else if let first = stops.first {
            mapView.animate(toLocation: first.coordinate)
            mapView.animate(toZoom: 13)
        } else if let userCoordinate {
            mapView.animate(toLocation: userCoordinate)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GooglePlannerMapView

        init(parent: GooglePlannerMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard
                let value = marker.userData as? String,
                let id = UUID(uuidString: value)
            else {
                return false
            }

            parent.selectedStopID = id
            return false
        }
    }
}
#endif

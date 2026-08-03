import MapKit

@MainActor
protocol RouteNavigationService {
    @discardableResult
    func openDirections(to stop: PlanStopSnapshot) -> Bool
}

@MainActor
final class AppleMapsRouteNavigationService: RouteNavigationService {
    @discardableResult
    func openDirections(to stop: PlanStopSnapshot) -> Bool {
        let placemark = MKPlacemark(coordinate: stop.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = stop.name
        return item.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }
}

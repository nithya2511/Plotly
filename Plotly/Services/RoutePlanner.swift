import CoreLocation
import Foundation

enum RoutePlanningMode: String, CaseIterable, Identifiable {
    case manual
    case shortest
    case farthestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Custom"
        case .shortest:
            return "Shortest"
        case .farthestFirst:
            return "Farthest First"
        }
    }

    var description: String {
        switch self {
        case .manual:
            return "Keep the order you arranged."
        case .shortest:
            return "Visit the nearest next stop each time."
        case .farthestFirst:
            return "Start with the farthest stop, then move to the nearest next stop."
        }
    }
}

enum RoutePlanner {
    static func orderedStopIDs(
        stops: [PlanStopSnapshot],
        mode: RoutePlanningMode,
        userCoordinate: CLLocationCoordinate2D?,
        fixedStartStopID: UUID?,
        fixedEndStopID: UUID?
    ) -> [UUID] {
        switch mode {
        case .manual:
            return stops.map(\.id)
        case .shortest:
            return shortestOrder(
                stops: stops,
                userCoordinate: userCoordinate,
                fixedStartStopID: fixedStartStopID,
                fixedEndStopID: fixedEndStopID
            ).map(\.id)
        case .farthestFirst:
            return farthestFirstOrder(
                stops: stops,
                userCoordinate: userCoordinate,
                fixedStartStopID: fixedStartStopID,
                fixedEndStopID: fixedEndStopID
            ).map(\.id)
        }
    }

    private static func shortestOrder(
        stops: [PlanStopSnapshot],
        userCoordinate: CLLocationCoordinate2D?,
        fixedStartStopID: UUID?,
        fixedEndStopID: UUID?
    ) -> [PlanStopSnapshot] {
        guard stops.count > 1 else { return stops }

        var remainingStops = stops
        var orderedStops: [PlanStopSnapshot] = []
        let fixedEndStop = removeStop(id: fixedEndStopID, from: &remainingStops)

        var currentCoordinate: CLLocationCoordinate2D
        if let fixedStartStop = removeStop(id: fixedStartStopID, from: &remainingStops) {
            orderedStops.append(fixedStartStop)
            currentCoordinate = fixedStartStop.coordinate
        } else if let userCoordinate {
            currentCoordinate = userCoordinate
        } else if let firstStop = remainingStops.first {
            orderedStops.append(firstStop)
            remainingStops.removeFirst()
            currentCoordinate = firstStop.coordinate
        } else {
            return []
        }

        while !remainingStops.isEmpty {
            let nearestIndex = nearestStopIndex(to: currentCoordinate, in: remainingStops)
            let nearestStop = remainingStops.remove(at: nearestIndex)
            orderedStops.append(nearestStop)
            currentCoordinate = nearestStop.coordinate
        }

        if let fixedEndStop {
            orderedStops.append(fixedEndStop)
        }

        return orderedStops
    }

    private static func farthestFirstOrder(
        stops: [PlanStopSnapshot],
        userCoordinate: CLLocationCoordinate2D?,
        fixedStartStopID: UUID?,
        fixedEndStopID: UUID?
    ) -> [PlanStopSnapshot] {
        guard fixedStartStopID == nil else {
            return shortestOrder(
                stops: stops,
                userCoordinate: userCoordinate,
                fixedStartStopID: fixedStartStopID,
                fixedEndStopID: fixedEndStopID
            )
        }

        var remainingStops = stops
        let fixedEndStop = removeStop(id: fixedEndStopID, from: &remainingStops)

        guard remainingStops.count > 1 else {
            return remainingStops + [fixedEndStop].compactMap { $0 }
        }

        let origin = userCoordinate ?? remainingStops.first?.coordinate
        guard let origin else { return stops }

        let farthestIndex = farthestStopIndex(to: origin, in: remainingStops)
        let firstStop = remainingStops.remove(at: farthestIndex)
        var orderedStops = [firstStop]
        var currentCoordinate = firstStop.coordinate

        while !remainingStops.isEmpty {
            let nearestIndex = nearestStopIndex(to: currentCoordinate, in: remainingStops)
            let nearestStop = remainingStops.remove(at: nearestIndex)
            orderedStops.append(nearestStop)
            currentCoordinate = nearestStop.coordinate
        }

        if let fixedEndStop {
            orderedStops.append(fixedEndStop)
        }

        return orderedStops
    }

    private static func removeStop(id: UUID?, from stops: inout [PlanStopSnapshot]) -> PlanStopSnapshot? {
        guard let id, let index = stops.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return stops.remove(at: index)
    }

    private static func nearestStopIndex(
        to coordinate: CLLocationCoordinate2D,
        in stops: [PlanStopSnapshot]
    ) -> Int {
        stops.indices.min { lhs, rhs in
            distance(from: coordinate, to: stops[lhs].coordinate) < distance(from: coordinate, to: stops[rhs].coordinate)
        } ?? stops.startIndex
    }

    private static func farthestStopIndex(
        to coordinate: CLLocationCoordinate2D,
        in stops: [PlanStopSnapshot]
    ) -> Int {
        stops.indices.max { lhs, rhs in
            distance(from: coordinate, to: stops[lhs].coordinate) < distance(from: coordinate, to: stops[rhs].coordinate)
        } ?? stops.startIndex
    }

    private static func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}

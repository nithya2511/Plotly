import Foundation
import SwiftData

@MainActor
protocol PlanRepository {
    func loadCurrentPlan() throws -> PlanSnapshot
    func addStop(_ place: PlaceDetails) throws -> PlanSnapshot
    func updateStopNote(id: UUID, note: String) throws -> PlanSnapshot
    func removeStop(id: UUID) throws -> PlanSnapshot
}

@MainActor
final class SwiftDataPlanRepository: PlanRepository {
    private let modelContext: ModelContext
    private let currentPlanTitle = "Today's Route"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadCurrentPlan() throws -> PlanSnapshot {
        let plan = try currentPlan()
        return try snapshot(for: plan)
    }

    func addStop(_ place: PlaceDetails) throws -> PlanSnapshot {
        let plan = try currentPlan()
        let stops = try stops(for: plan.id)

        if let existing = stops.first(where: { $0.placeID == place.placeID }) {
            existing.updatedAt = Date()
            try modelContext.save()
            return try snapshot(for: plan)
        }

        let nextIndex = (stops.map(\.sortIndex).max() ?? -1) + 1
        let stop = PlanStop(
            planID: plan.id,
            placeID: place.placeID,
            name: place.name,
            formattedAddress: place.formattedAddress,
            latitude: place.latitude,
            longitude: place.longitude,
            sortIndex: nextIndex
        )
        plan.updatedAt = Date()
        modelContext.insert(stop)
        try modelContext.save()
        return try snapshot(for: plan)
    }

    func updateStopNote(id: UUID, note: String) throws -> PlanSnapshot {
        let plan = try currentPlan()
        guard let stop = try stops(for: plan.id).first(where: { $0.id == id }) else {
            return try snapshot(for: plan)
        }

        stop.note = note
        stop.updatedAt = Date()
        plan.updatedAt = Date()
        try modelContext.save()
        return try snapshot(for: plan)
    }

    func removeStop(id: UUID) throws -> PlanSnapshot {
        let plan = try currentPlan()
        let stops = try stops(for: plan.id)
        guard let stop = stops.first(where: { $0.id == id }) else {
            return try snapshot(for: plan)
        }

        modelContext.delete(stop)
        plan.updatedAt = Date()
        try modelContext.save()
        return try snapshot(for: plan)
    }

    private func currentPlan() throws -> Plan {
        var descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.isCurrent == true },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1

        if let plan = try modelContext.fetch(descriptor).first {
            if plan.title == "Current Plan" {
                plan.title = currentPlanTitle
                plan.updatedAt = Date()
                try modelContext.save()
            }
            return plan
        }

        let plan = Plan(title: currentPlanTitle, isCurrent: true)
        modelContext.insert(plan)
        try modelContext.save()
        return plan
    }

    private func stops(for planID: UUID) throws -> [PlanStop] {
        let descriptor = FetchDescriptor<PlanStop>(
            predicate: #Predicate { $0.planID == planID },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func snapshot(for plan: Plan) throws -> PlanSnapshot {
        PlanSnapshot(
            id: plan.id,
            title: plan.title,
            stops: try stops(for: plan.id).map(\.snapshot)
        )
    }
}

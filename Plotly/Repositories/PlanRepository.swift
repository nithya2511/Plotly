import Foundation
import SwiftData

@MainActor
protocol PlanRepository {
    func loadCurrentPlan() throws -> PlanSnapshot
    func loadBookmarkedPlans() throws -> [PlanSnapshot]
    func selectPlan(id: UUID) throws -> PlanSnapshot
    func createNewPlan() throws -> PlanSnapshot
    func addStop(_ place: PlaceDetails) throws -> PlanSnapshot
    func updatePlanDetails(title: String, isFavorite: Bool) throws -> PlanSnapshot
    func updateStopNote(id: UUID, note: String) throws -> PlanSnapshot
    func updateStopCompletion(id: UUID, isCompleted: Bool) throws -> PlanSnapshot
    func removeStop(id: UUID) throws -> PlanSnapshot
    func moveStops(from source: IndexSet, to destination: Int) throws -> PlanSnapshot
    func reorderStops(_ orderedStopIDs: [UUID]) throws -> PlanSnapshot
}

@MainActor
final class SwiftDataPlanRepository: PlanRepository {
    private let modelContext: ModelContext
    private let userID: UUID
    private let currentPlanTitle = "Today's Route"

    init(modelContext: ModelContext, userID: UUID) {
        self.modelContext = modelContext
        self.userID = userID
    }

    func loadCurrentPlan() throws -> PlanSnapshot {
        let plan = try currentPlan()
        return try snapshot(for: plan)
    }

    func loadBookmarkedPlans() throws -> [PlanSnapshot] {
        let userID = userID
        let descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.userID == userID && $0.isFavorite == true },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { try snapshot(for: $0) }
    }

    func selectPlan(id: UUID) throws -> PlanSnapshot {
        let userID = userID
        let descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.userID == userID }
        )
        let plans = try modelContext.fetch(descriptor)
        guard let selectedPlan = plans.first(where: { $0.id == id }) else {
            return try loadCurrentPlan()
        }

        for plan in plans {
            plan.isCurrent = plan.id == id
            if plan.id == id {
                plan.updatedAt = Date()
            }
        }

        try modelContext.save()
        return try snapshot(for: selectedPlan)
    }

    func createNewPlan() throws -> PlanSnapshot {
        let userID = userID
        let descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.userID == userID }
        )
        let plans = try modelContext.fetch(descriptor)
        for plan in plans {
            plan.isCurrent = false
        }

        let newPlan = Plan(userID: userID, title: currentPlanTitle, isCurrent: true)
        modelContext.insert(newPlan)
        try modelContext.save()
        return try snapshot(for: newPlan)
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

    func updatePlanDetails(title: String, isFavorite: Bool) throws -> PlanSnapshot {
        let plan = try currentPlan()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.title = trimmedTitle.isEmpty ? currentPlanTitle : trimmedTitle
        plan.isFavorite = isFavorite
        plan.updatedAt = Date()
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

    func updateStopCompletion(id: UUID, isCompleted: Bool) throws -> PlanSnapshot {
        let plan = try currentPlan()
        guard let stop = try stops(for: plan.id).first(where: { $0.id == id }) else {
            return try snapshot(for: plan)
        }

        stop.isCompleted = isCompleted
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

    func moveStops(from source: IndexSet, to destination: Int) throws -> PlanSnapshot {
        let plan = try currentPlan()
        let orderedStops = reorderedStops(try stops(for: plan.id), from: source, to: destination)
        return try saveOrder(orderedStops, in: plan)
    }

    func reorderStops(_ orderedStopIDs: [UUID]) throws -> PlanSnapshot {
        let plan = try currentPlan()
        let stops = try stops(for: plan.id)
        let stopsByID = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) })
        var seenIDs = Set<UUID>()
        var orderedStops = orderedStopIDs.compactMap { id -> PlanStop? in
            guard let stop = stopsByID[id], seenIDs.insert(id).inserted else { return nil }
            return stop
        }

        orderedStops.append(contentsOf: stops.filter { !seenIDs.contains($0.id) })
        return try saveOrder(orderedStops, in: plan)
    }

    private func saveOrder(_ orderedStops: [PlanStop], in plan: Plan) throws -> PlanSnapshot {
        guard !orderedStops.isEmpty else {
            return try snapshot(for: plan)
        }

        for (index, stop) in orderedStops.enumerated() {
            stop.sortIndex = index
            stop.updatedAt = Date()
        }

        plan.updatedAt = Date()
        try modelContext.save()
        return try snapshot(for: plan)
    }

    private func reorderedStops(_ stops: [PlanStop], from source: IndexSet, to destination: Int) -> [PlanStop] {
        let movingStops = source.sorted().map { stops[$0] }
        var remainingStops = stops.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        remainingStops.insert(contentsOf: movingStops, at: adjustedDestination)
        return remainingStops
    }

    private func currentPlan() throws -> Plan {
        let userID = userID
        var descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.userID == userID && $0.isCurrent == true },
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

        if let legacyPlan = try claimLegacyCurrentPlan() {
            return legacyPlan
        }

        let plan = Plan(userID: userID, title: currentPlanTitle, isCurrent: true)
        modelContext.insert(plan)
        try modelContext.save()
        return plan
    }

    private func claimLegacyCurrentPlan() throws -> Plan? {
        var descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.userID == nil && $0.isCurrent == true },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1

        guard let plan = try modelContext.fetch(descriptor).first else {
            return nil
        }

        let userID = userID
        let userPlansDescriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.userID == userID }
        )
        for userPlan in try modelContext.fetch(userPlansDescriptor) {
            userPlan.isCurrent = false
        }

        plan.userID = userID
        plan.isCurrent = true
        if plan.title == "Current Plan" {
            plan.title = currentPlanTitle
        }
        plan.updatedAt = Date()
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
            isFavorite: plan.isFavorite,
            stops: try stops(for: plan.id).map(\.snapshot)
        )
    }
}

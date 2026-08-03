import Foundation
import SwiftData

@MainActor
protocol AccountRepository {
    func loadAccounts() throws -> [UserAccountSnapshot]
    func account(id: UUID) throws -> UserAccountSnapshot?
    func signIn(displayName: String, email: String) throws -> UserAccountSnapshot
    func selectAccount(id: UUID) throws -> UserAccountSnapshot?
}

@MainActor
final class SwiftDataAccountRepository: AccountRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadAccounts() throws -> [UserAccountSnapshot] {
        let descriptor = FetchDescriptor<UserAccount>(
            sortBy: [SortDescriptor(\.lastSignedInAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    func account(id: UUID) throws -> UserAccountSnapshot? {
        try userAccount(id: id)?.snapshot
    }

    func signIn(displayName: String, email: String) throws -> UserAccountSnapshot {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = normalizedEmail.split(separator: "@").first.map(String.init) ?? "Traveler"
        let resolvedName = trimmedName.isEmpty ? fallbackName : trimmedName

        if let existingAccount = try account(email: normalizedEmail) {
            existingAccount.displayName = resolvedName
            existingAccount.lastSignedInAt = Date()
            try modelContext.save()
            return existingAccount.snapshot
        }

        let account = UserAccount(displayName: resolvedName, email: normalizedEmail)
        modelContext.insert(account)
        try modelContext.save()
        return account.snapshot
    }

    func selectAccount(id: UUID) throws -> UserAccountSnapshot? {
        guard let account = try userAccount(id: id) else {
            return nil
        }

        account.lastSignedInAt = Date()
        try modelContext.save()
        return account.snapshot
    }

    private func userAccount(id: UUID) throws -> UserAccount? {
        var descriptor = FetchDescriptor<UserAccount>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func account(email: String) throws -> UserAccount? {
        var descriptor = FetchDescriptor<UserAccount>(
            predicate: #Predicate { $0.email == email }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

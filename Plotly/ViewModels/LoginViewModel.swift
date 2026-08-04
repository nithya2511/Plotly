import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var displayName = ""
    @Published var email = ""
    @Published private(set) var savedAccounts: [UserAccountSnapshot] = []
    @Published var errorMessage: String?

    var canSignIn: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let repository: AccountRepository
    private let onSignedIn: (UserAccountSnapshot) -> Void
    private let onSkipped: (UserAccountSnapshot) -> Void

    init(
        repository: AccountRepository,
        onSignedIn: @escaping (UserAccountSnapshot) -> Void,
        onSkipped: @escaping (UserAccountSnapshot) -> Void
    ) {
        self.repository = repository
        self.onSignedIn = onSignedIn
        self.onSkipped = onSkipped
    }

    func load() {
        do {
            savedAccounts = try repository.loadAccounts()
        } catch {
            errorMessage = UserFacingErrorMessage.loadAccounts
        }
    }

    func signIn() {
        guard canSignIn else { return }

        do {
            let account = try repository.signIn(displayName: displayName, email: email)
            onSignedIn(account)
        } catch {
            errorMessage = UserFacingErrorMessage.signIn
        }
    }

    func signInWithApple(userIdentifier: String, email: String?, fullName: String?) {
        do {
            let account = try repository.signInWithApple(
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )
            onSignedIn(account)
        } catch {
            errorMessage = UserFacingErrorMessage.signIn
        }
    }

    func selectAccount(_ account: UserAccountSnapshot) {
        do {
            guard let selectedAccount = try repository.selectAccount(id: account.id) else {
                errorMessage = UserFacingErrorMessage.accountUnavailable
                return
            }
            onSignedIn(selectedAccount)
        } catch {
            errorMessage = UserFacingErrorMessage.signIn
        }
    }

    func continueAsGuest() {
        onSkipped(.guest)
    }

    func showError(_ message: String) {
        errorMessage = message
    }
}

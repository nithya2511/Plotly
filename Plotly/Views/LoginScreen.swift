import AuthenticationServices
import SwiftUI

struct LoginScreen: View {
    @StateObject private var viewModel: LoginViewModel

    init(viewModel: LoginViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemBlue).opacity(0.12),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        signInForm

                        if !viewModel.savedAccounts.isEmpty {
                            savedAccounts
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 34)
                }
            }
            .navigationBarHidden(true)
            .task {
                viewModel.load()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            RouteSplashMark()
                .frame(width: 70, height: 70)

            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Plotly")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Sign in to keep routes, notes, and bookmarks under your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signInForm: some View {
        VStack(spacing: 14) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color(.systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                viewModel.continueAsGuest()
            } label: {
                Text("Continue as Guest")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                viewModel.showError(UserFacingErrorMessage.appleSignInInvalidCredential)
                return
            }

            viewModel.signInWithApple(
                userIdentifier: credential.user,
                email: credential.email,
                fullName: formattedName(from: credential.fullName)
            )
        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            viewModel.showError(UserFacingErrorMessage.signIn)
        }
    }

    private func formattedName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private var savedAccounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent accounts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(viewModel.savedAccounts) { account in
                    Button {
                        viewModel.selectAccount(account)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color(.systemBlue))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)

                    if account.id != viewModel.savedAccounts.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(.secondarySystemBackground).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

#Preview {
    LoginScreen(
        viewModel: LoginViewModel(
            repository: PreviewAccountRepository(),
            onSignedIn: { _ in },
            onSkipped: { _ in }
        )
    )
}

private final class PreviewAccountRepository: AccountRepository {
    func loadAccounts() throws -> [UserAccountSnapshot] {
        [
            UserAccountSnapshot(id: UUID(), displayName: "Nithya", email: "nithya@example.com")
        ]
    }

    func account(id: UUID) throws -> UserAccountSnapshot? {
        nil
    }

    func signIn(displayName: String, email: String) throws -> UserAccountSnapshot {
        UserAccountSnapshot(id: UUID(), displayName: displayName, email: email)
    }

    func signInWithApple(userIdentifier: String, email: String?, fullName: String?) throws -> UserAccountSnapshot {
        UserAccountSnapshot(
            id: UUID(),
            displayName: fullName ?? "Apple User",
            email: email ?? "Apple account"
        )
    }

    func selectAccount(id: UUID) throws -> UserAccountSnapshot? {
        try loadAccounts().first
    }
}

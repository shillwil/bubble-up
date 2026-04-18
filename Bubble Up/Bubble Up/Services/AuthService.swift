import SwiftUI
import Foundation
import Supabase
import AuthenticationServices

/// Manages user authentication via Supabase Auth.
@Observable
@MainActor
final class AuthService {
    private(set) var currentUserID: String?
    private(set) var currentUserEmail: String?
    private(set) var isAuthenticated = false
    private(set) var isFriendsAndFamily = false

    private let keychainService: KeychainService
    private let client: SupabaseClient

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
        self.client = SupabaseClientProvider.shared

        // Listen for auth state changes
        Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                switch event {
                case .signedIn, .tokenRefreshed:
                    if let user = session?.user {
                        self.currentUserID = user.id.uuidString
                        self.currentUserEmail = user.email
                        self.isAuthenticated = true
                        await self.checkFriendsAndFamilyStatus()
                    }
                case .signedOut:
                    self.currentUserID = nil
                    self.currentUserEmail = nil
                    self.isAuthenticated = false
                    self.isFriendsAndFamily = false
                default:
                    break
                }
            }
        }
    }

    // MARK: - Email/Password Auth

    func signInWithEmail(_ email: String, password: String) async throws {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        currentUserID = session.user.id.uuidString
        currentUserEmail = session.user.email
        isAuthenticated = true
        await checkFriendsAndFamilyStatus()
    }

    func signUpWithEmail(_ email: String, password: String, inviteCode: String? = nil) async throws {
        // 1. Create the account first (we need a session before calling Edge Functions)
        let response = try await client.auth.signUp(
            email: email,
            password: password
        )

        currentUserID = response.user.id.uuidString
        currentUserEmail = response.user.email
        isAuthenticated = true

        // 2. Redeem invite code if provided (now we have an auth token)
        if let code = inviteCode {
            do {
                try await redeemInviteCode(code)
                isFriendsAndFamily = true
            } catch {
                // Account created but code was invalid — user just won't be F&F
                print("Invite code redemption failed: \(error)")
            }
        }
    }

    // MARK: - Apple Sign-In

    func signInWithApple() async throws {
        let result = try await performAppleSignIn()

        guard let credential = result.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.appleSignInFailed
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: tokenString
            )
        )

        currentUserID = session.user.id.uuidString
        currentUserEmail = session.user.email
        isAuthenticated = true
        await checkFriendsAndFamilyStatus()
    }

    private func performAppleSignIn() async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.email, .fullName]

            let delegate = AppleSignInDelegate(continuation: continuation)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate

            // Retain delegate for the duration of the request
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            controller.performRequests()
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await client.auth.signOut()
        currentUserID = nil
        currentUserEmail = nil
        isAuthenticated = false
        isFriendsAndFamily = false
    }

    // MARK: - Invite Code

    func validateInviteCode(_ code: String) async throws -> Bool {
        struct ValidateResponse: Decodable {
            let valid: Bool
        }

        let result: ValidateResponse = try await client.functions.invoke(
            "validate-invite-code",
            options: .init(body: ["code": code, "action": "check"])
        )
        return result.valid
    }

    private func redeemInviteCode(_ code: String) async throws {
        let _ = try await client.functions.invoke(
            "validate-invite-code",
            options: .init(body: ["code": code, "action": "redeem"])
        )
    }

    // MARK: - Session Restoration

    func restoreSession() async {
        do {
            let session = try await client.auth.session
            currentUserID = session.user.id.uuidString
            currentUserEmail = session.user.email
            isAuthenticated = true
            await checkFriendsAndFamilyStatus()
        } catch {
            // No valid session — user stays on login screen
            isAuthenticated = false
        }
    }

    // MARK: - F&F Status

    private func checkFriendsAndFamilyStatus() async {
        guard let userID = currentUserID, let uuid = UUID(uuidString: userID) else { return }

        do {
            let codes: [InviteCodeRow] = try await client
                .from("invite_codes")
                .select("id")
                .eq("claimed_by", value: uuid)
                .limit(1)
                .execute()
                .value

            isFriendsAndFamily = !codes.isEmpty
        } catch {
            isFriendsAndFamily = false
        }
    }
}

// MARK: - Error Types

enum AuthError: Error, LocalizedError {
    case invalidInviteCode
    case signUpFailed
    case appleSignInFailed

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode: return "Invalid or already claimed invite code"
        case .signUpFailed: return "Account creation failed. Please try again."
        case .appleSignInFailed: return "Apple Sign-In failed. Please try again."
        }
    }
}

// MARK: - Apple Sign-In Delegate

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let continuation: CheckedContinuation<ASAuthorization, Error>

    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
}

// MARK: - Helper Types

private struct InviteCodeRow: Decodable {
    let id: UUID
}

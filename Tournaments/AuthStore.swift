//
//  AuthStore.swift
//  x-court
//

import AuthenticationServices
import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    private(set) var user: User?
    private(set) var isBootstrapping = true
    private(set) var isSubmitting = false
    var errorMessage: String?
    var infoMessage: String?

    private let auth: AuthService

    var isSignedIn: Bool { user != nil }

    init(auth: AuthService = AuthService()) {
        self.auth = auth
    }

    func bootstrap() async {
        isBootstrapping = true
        errorMessage = nil
        defer { isBootstrapping = false }

        do {
            user = try await auth.currentUser()
        } catch {
            user = nil
        }
    }

    func login(email: String, password: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }

        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        // Prefer an existing cookie session over posting credentials again.
        if let existing = await auth.existingSessionUser() {
            user = existing
            return
        }

        do {
            user = try await auth.login(email: trimmed, password: password)
        } catch let APIError.http(_, message, code) where code == "EMAIL_NOT_VERIFIED" {
            errorMessage = message
        } catch {
            // Legacy servers still return 403 "Already signed in".
            let text = error.localizedDescription
            if text.localizedCaseInsensitiveContains("Already signed in") {
                if let existing = await auth.existingSessionUser() {
                    user = existing
                    return
                }
                await auth.forceClearSession()
                do {
                    user = try await auth.login(email: trimmed, password: password)
                    return
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
            }
            errorMessage = text
        }
    }

    /// Pull a live session cookie into the store (login sheet / cold start edge cases).
    func adoptExistingSessionIfNeeded() async {
        guard user == nil else { return }
        if let existing = await auth.existingSessionUser() {
            user = existing
            errorMessage = nil
        }
    }

    func register(name: String, email: String, password: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Name, email, and password are required."
            return false
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        do {
            infoMessage = try await auth.register(
                name: trimmedName,
                email: trimmedEmail,
                password: password
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resendVerification(email: String) async throws -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        defer { isSubmitting = false }
        return try await auth.resendVerification(email: trimmed)
    }

    func forgotPassword(email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Email is required."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        do {
            infoMessage = try await auth.forgotPassword(email: trimmed)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private var appleRawNonce: String?

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let raw = AppleSignInCrypto.randomNonce()
        appleRawNonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInCrypto.sha256Hex(raw)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        infoMessage = nil
        defer { appleRawNonce = nil }

        switch result {
        case .failure(let error):
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let rawNonce = appleRawNonce, !rawNonce.isEmpty else {
                errorMessage = AppleSignInError.missingNonce.localizedDescription
                return
            }
            do {
                let apple = try AppleSignInCrypto.result(from: authorization, rawNonce: rawNonce)
                user = try await auth.loginWithApple(
                    identityToken: apple.identityToken,
                    nonce: apple.nonce,
                    name: apple.fullName
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loginWithOAuth(provider: OAuthProvider) async {
        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        do {
            guard var components = URLComponents(
                url: APIConfig.baseURL.appending(path: "api/auth/oauth/\(provider.rawValue)"),
                resolvingAgainstBaseURL: false
            ) else {
                errorMessage = "Could not start \(provider.title) sign-in."
                return
            }
            components.queryItems = [URLQueryItem(name: "client", value: "ios")]
            guard let url = components.url else {
                errorMessage = "Could not start \(provider.title) sign-in."
                return
            }

            let callback = try await AuthSessionBrowser.open(url: url)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
                errorMessage = error
                return
            }
            guard let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty else {
                errorMessage = "\(provider.title) sign-in did not return a session."
                return
            }
            user = try await auth.applySessionToken(token)
        } catch AuthSessionBrowser.SessionError.cancelled {
            // User dismissed the sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await auth.logout()
            user = nil
        } catch {
            user = nil
            errorMessage = error.localizedDescription
        }
    }

    func saveAccount(name: String, email: String, phone: String, picture: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPicture = picture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            errorMessage = "Name and email are required."
            return false
        }
        guard !trimmedPicture.isEmpty else {
            errorMessage = "Pick a profile picture."
            return false
        }
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        do {
            let saved = try await auth.updateAccount(
                name: trimmedName,
                email: trimmedEmail,
                profilePicture: trimmedPicture,
                phone: trimmedPhone.isEmpty ? "" : trimmedPhone
            )
            user = saved.user
            if saved.emailChanged {
                infoMessage = "Check \(saved.user.email) to verify the new address."
            } else {
                infoMessage = "Profile updated."
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAccount(confirm: String, password: String?) async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await auth.deleteAccount(confirm: confirm, password: password)
            user = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func applyUser(_ user: User) {
        self.user = user
    }

    /// `xcourt://auth/verify-email?token=…` or `?session=…` from the verify email / web page.
    func handleVerifyEmailDeepLink(_ url: URL) async {
        guard url.scheme == "xcourt",
              url.host == "auth",
              url.path == "/verify-email" || url.path == "verify-email"
        else { return }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let session = items.first(where: { $0.name == "session" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = items.first(where: { $0.name == "token" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        do {
            if let session, !session.isEmpty {
                user = try await auth.applySessionToken(session)
                infoMessage = "Email verified. You're signed in."
                return
            }
            if let token, !token.isEmpty {
                user = try await auth.verifyEmail(token: token)
                infoMessage = "Email verified. You're signed in."
                return
            }
            errorMessage = "This verification link is missing or incomplete."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }
}

enum OAuthProvider: String, Sendable {
    case google
    case facebook

    var title: String {
        switch self {
        case .google: return "Google"
        case .facebook: return "Facebook"
        }
    }
}

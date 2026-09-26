//
//  AuthSessionBrowser.swift
//  x-court
//
//  Opens PayPal / PayMongo in ASWebAuthenticationSession so the gateway's
//  HTTPS return can bounce to xcourt:// and dismiss back into the app.
//

import AuthenticationServices
import UIKit

enum AuthSessionBrowser {
    static let callbackScheme = "xcourt"

    enum SessionError: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Sign-in was cancelled."
            case .failed(let message): return message
        }
    }
}

    @MainActor
    static func open(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let coordinator = AuthSessionCoordinator()
            coordinator.presentationAnchorProvider = {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)
                    ?? ASPresentationAnchor()
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                defer { coordinator.retainSelf = nil }
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: SessionError.cancelled)
                    } else {
                        continuation.resume(throwing: SessionError.failed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: SessionError.cancelled)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = coordinator
            // Keep cookies so returning PayPal users stay signed in.
            session.prefersEphemeralWebBrowserSession = false
            coordinator.session = session
            coordinator.retainSelf = coordinator

            if !session.start() {
                coordinator.retainSelf = nil
                continuation.resume(throwing: SessionError.failed("Could not open sign-in browser."))
            }
        }
    }
}

private final class AuthSessionCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    var session: ASWebAuthenticationSession?
    /// Keep the coordinator alive until the session callback fires.
    var retainSelf: AuthSessionCoordinator?
    var presentationAnchorProvider: (() -> ASPresentationAnchor)?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchorProvider?() ?? ASPresentationAnchor()
    }
}

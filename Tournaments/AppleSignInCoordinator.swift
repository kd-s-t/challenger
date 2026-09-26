//
//  AppleSignInCoordinator.swift
//  x-court
//

import AuthenticationServices
import CryptoKit
import Foundation

enum AppleSignInError: LocalizedError {
    case cancelled
    case missingIdentityToken
    case missingNonce
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in with Apple was cancelled."
        case .missingIdentityToken:
            return "Apple did not return an identity token."
        case .missingNonce:
            return "Apple sign-in nonce was missing."
        case .failed(let message):
            return message
        }
    }
}

struct AppleSignInResult: Sendable {
    let identityToken: String
    let nonce: String
    let fullName: String?
}

@MainActor
final class AppleSignInPresenter: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private var controller: ASAuthorizationController?
  var onFinish: ((Result<ASAuthorization, Error>) -> Void)?

  func start(_ prepare: (ASAuthorizationAppleIDRequest) -> Void) {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    prepare(request)
    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.presentationContextProvider = self
    self.controller = controller
    controller.performRequests()
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
    return window ?? ASPresentationAnchor()
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    onFinish?(.success(authorization))
    self.controller = nil
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    onFinish?(.failure(error))
    self.controller = nil
  }
}

enum AppleSignInCrypto {
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                randoms = (0..<16).map { _ in UInt8.random(in: 0...255) }
            }
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func formattedName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func result(
        from authorization: ASAuthorization,
        rawNonce: String
    ) throws -> AppleSignInResult {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleSignInError.missingIdentityToken
        }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty
        else {
            throw AppleSignInError.missingIdentityToken
        }
        return AppleSignInResult(
            identityToken: identityToken,
            nonce: rawNonce,
            fullName: formattedName(credential.fullName)
        )
    }
}

//
//  AuthService.swift
//  x-court
//

import Foundation

struct LoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable, Sendable {
    let name: String
    let email: String
    let password: String
    let phone: String?
    let client: String
}

struct EmailOnlyRequest: Encodable, Sendable {
    let email: String
}

struct LogoutResponse: Decodable, Sendable {
    let ok: Bool
}

struct AuthMessageResponse: Decodable, Sendable {
    let message: String?
    let email: String?
    let error: String?
}

private func photoKind(_ data: Data) throws -> (mime: String, name: String) {
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
        return ("image/png", "avatar.png")
    }
    if data.starts(with: [0xFF, 0xD8]) {
        return ("image/jpeg", "avatar.jpg")
    }
    if data.count >= 12, data.starts(with: [0x52, 0x49, 0x46, 0x46]),
       String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WEBP" {
        return ("image/webp", "avatar.webp")
    }
    if data.count >= 12,
       String(data: data.subdata(in: 4..<8), encoding: .ascii) == "ftyp" {
        let brand = String(data: data.subdata(in: 8..<12), encoding: .ascii) ?? ""
        if brand == "heic" || brand == "heif" || brand == "mif1" {
            return ("image/heic", "avatar.heic")
        }
    }
    throw APIError.http(status: 400, message: "Photo must be JPEG, PNG, WebP, or HEIC", code: nil)
}

struct AuthService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func currentUser() async throws -> User? {
        do {
            let response: UserResponse = try await client.get(path: "/api/auth/me")
            return response.user
        } catch let APIError.http(status, _, _) where status == 401 {
            return nil
        }
    }

    func login(email: String, password: String) async throws -> User {
        // Newer API returns the existing user; older builds 403.
        do {
            return try await postLogin(email: email, password: password)
        } catch let error as APIError where error.isAlreadySignedIn {
            if let existing = try? await currentUser() {
                return existing
            }
            await forceClearSession()
            return try await postLogin(email: email, password: password)
        }
    }

    /// If a session cookie exists but the store is empty, return that user.
    func existingSessionUser() async -> User? {
        try? await currentUser()
    }

    /// Clear server session (best-effort) and wipe local auth cookies.
    func forceClearSession() async {
        do {
            let _: LogoutResponse = try await client.delete(path: "/api/auth/login")
        } catch {
            // Still wipe local jar.
        }
        await client.clearAuthCookies()
    }

    private func postLogin(email: String, password: String) async throws -> User {
        let response: UserResponse = try await client.post(
            path: "/api/auth/login",
            body: LoginRequest(email: email, password: password)
        )
        guard let user = response.user else {
            throw APIError.invalidResponse
        }
        return user
    }

    func register(name: String, email: String, password: String) async throws -> String {
        let response: AuthMessageResponse = try await client.post(
            path: "/api/auth/register",
            body: RegisterRequest(
                name: name,
                email: email,
                password: password,
                phone: nil,
                client: "ios"
            )
        )
        return response.message
            ?? "Check your email to verify your account before signing in."
    }

    func resendVerification(email: String) async throws -> String {
        struct Body: Encodable {
            let email: String
            let client: String
        }
        let response: AuthMessageResponse = try await client.post(
            path: "/api/auth/resend-verification",
            body: Body(email: email, client: "ios")
        )
        return response.message
            ?? "If that account needs verification, we sent a new email."
    }

    func forgotPassword(email: String) async throws -> String {
        let response: AuthMessageResponse = try await client.post(
            path: "/api/auth/forgot-password",
            body: EmailOnlyRequest(email: email)
        )
        return response.message
            ?? "If an account exists for that email, we sent a password reset link."
    }

    func logout() async throws {
        do {
            let _: LogoutResponse = try await client.delete(path: "/api/auth/login")
        } catch {
            await client.clearAuthCookies()
            throw error
        }
        await client.clearAuthCookies()
    }

    func updateAccount(
        name: String,
        email: String,
        profilePicture: String,
        phone: String?
    ) async throws -> (user: User, emailChanged: Bool) {
        struct Body: Encodable {
            let name: String
            let email: String
            let profilePicture: String
            let phone: String?

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(name, forKey: .name)
                try c.encode(email, forKey: .email)
                try c.encode(profilePicture, forKey: .profilePicture)
                try c.encode(phone ?? "", forKey: .phone)
            }

            enum CodingKeys: String, CodingKey {
                case name, email, profilePicture, phone
            }
        }
        struct Resp: Decodable {
            let user: User
            let emailChanged: Bool?
        }
        let response: Resp = try await client.patch(
            path: "/api/profile",
            body: Body(
                name: name,
                email: email,
                profilePicture: profilePicture,
                phone: phone
            )
        )
        return (response.user, response.emailChanged == true)
    }

    func profileDetails() async throws -> (user: User, avatars: AvatarEligibility) {
        struct Body: Decodable {
            let user: User
            let avatars: AvatarEligibility
        }
        let body: Body = try await client.get(path: "/api/profile")
        return (body.user, body.avatars)
    }

    func verifyPhone(code: String) async throws {
        struct Body: Encodable {
            let action: String
            let code: String
        }
        struct Resp: Decodable { let user: User? }
        let response: Resp = try await client.post(
            path: "/api/auth/phone/profile",
            body: Body(action: "verify", code: code)
        )
        _ = response
    }

    func resendPhoneCode() async throws {
        struct Body: Encodable {
            let action: String
        }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.post(
            path: "/api/auth/phone/profile",
            body: Body(action: "resend")
        )
    }

    func updatePhoto(user: User, image: Data) async throws -> User {
        let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            throw APIError.http(status: 400, message: "Add your name before a photo.", code: nil)
        }
        let kind = try photoKind(image)
        var fields = [
            "name": name,
            "email": user.email,
        ]
        let phone = user.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !phone.isEmpty {
            fields["phone"] = phone
        }
        struct Resp: Decodable { let user: User }
        let response: Resp = try await client.uploadMultipart(
            path: "/api/profile",
            method: "PATCH",
            fields: fields,
            fileField: "file",
            fileName: kind.name,
            mimeType: kind.mime,
            fileData: image
        )
        return response.user
    }

    /// Permanently delete the signed-in account (server clears the session cookie).
    func deleteAccount(confirm: String, password: String?) async throws {
        struct Body: Encodable {
            let confirm: String
            let password: String?
        }
        struct Resp: Decodable {
            let ok: Bool?
            let error: String?
        }
        let _: Resp = try await client.delete(
            path: "/api/account",
            body: Body(confirm: confirm, password: password)
        )
        await client.clearAuthCookies()
    }

    func loginWithApple(identityToken: String, nonce: String, name: String?) async throws -> User {
        struct Body: Encodable {
            let identityToken: String
            let nonce: String
            let name: String?
        }
        let response: UserResponse = try await client.post(
            path: "/api/auth/oauth/apple",
            body: Body(identityToken: identityToken, nonce: nonce, name: name)
        )
        guard let user = response.user else {
            throw APIError.invalidResponse
        }
        return user
    }

    func applySessionToken(_ token: String) async throws -> User {
        await client.setSessionToken(token)
        guard let user = try await currentUser() else {
            throw APIError.invalidResponse
        }
        return user
    }

    /// Consume an email verification token (sets session cookie on success).
    func verifyEmail(token: String) async throws -> User {
        struct Body: Encodable {
            let token: String
        }
        struct Resp: Decodable {
            let ok: Bool?
            let sessionToken: String?
            let error: String?
        }
        let response: Resp = try await client.post(
            path: "/api/auth/verify-email",
            body: Body(token: token)
        )
        if let session = response.sessionToken, !session.isEmpty {
            return try await applySessionToken(session)
        }
        guard let user = try await currentUser() else {
            throw APIError.invalidResponse
        }
        return user
    }
}

//
//  User.swift
//  x-court
//

import Foundation

struct User: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let email: String
    let name: String?
    let role: String
    /// All assigned roles (web `roles[]`). Missing on older API builds.
    let roles: [String]?
    let emailVerified: Bool
    let phone: String?
    let phoneVerified: Bool
    let profilePicture: String?
    /// Path from API (`/profiles/…` or `/s3local/profiles/…`).
    let profilePictureUrl: String?
    /// False until the first-login welcome overlay is completed or skipped.
    var welcomeSeen: Bool?
    /// True when email/password sign-in is configured. Missing on older API builds.
    let hasPassword: Bool?

    enum CodingKeys: String, CodingKey {
        case id, email, name, role, roles, emailVerified, phone, phoneVerified
        case profilePicture, profilePictureUrl, welcomeSeen, hasPassword
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "user"
        roles = try c.decodeIfPresent([String].self, forKey: .roles)
        emailVerified = try c.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        phoneVerified = try c.decodeIfPresent(Bool.self, forKey: .phoneVerified) ?? true
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        profilePictureUrl = try c.decodeIfPresent(String.self, forKey: .profilePictureUrl)
        welcomeSeen = try c.decodeIfPresent(Bool.self, forKey: .welcomeSeen)
        hasPassword = try c.decodeIfPresent(Bool.self, forKey: .hasPassword)
    }

    /// Missing flag means an API build without the field — never block on it.
    var hasSeenWelcome: Bool { welcomeSeen ?? true }

    /// Treat missing as true so password is requested when the flag is absent.
    var requiresPasswordForDeletion: Bool { hasPassword ?? true }

    /// Full URL for AsyncImage — always hits the API host.
    var avatarURL: URL? {
        let raw = (profilePictureUrl ?? profilePicture)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let path = raw.hasPrefix("/") ? raw : "/profiles/\(raw)"
        return URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL
    }

    /// Public profile page (`/u/{id}`; web also accepts username).
    var publicProfileURL: URL? {
        guard !id.isEmpty else { return nil }
        return APIConfig.baseURL.appending(path: "u").appending(path: id)
    }
}

struct UserResponse: Codable, Sendable {
    let user: User?
}

struct AuthErrorBody: Codable, Sendable {
    let error: String?
    let code: String?
    let email: String?
}

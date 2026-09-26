//
//  APIClient.swift
//  x-court
//

import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case http(status: Int, message: String, code: String?)
    case decoding(String)
    case missingCSRF

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Unexpected server response."
        case .http(_, let message, _):
            return message
        case .decoding(let detail):
            return "Could not read server response. \(detail)"
        case .missingCSRF:
            return "Could not obtain a CSRF token from the server."
        }
    }

    var isAlreadySignedIn: Bool {
        if case .http(let status, let message, _) = self {
            return status == 403
                && message.localizedCaseInsensitiveContains("Already signed in")
        }
        return false
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get<T: Decodable>(path: String) async throws -> T {
        let request = try await makeRequest(path: path, method: "GET", body: nil as EmptyBody?)
        return try await send(request)
    }

    func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let request = try await makeRequest(path: path, method: "POST", body: body)
        return try await send(request)
    }

    func patch<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let request = try await makeRequest(path: path, method: "PATCH", body: body)
        return try await send(request)
    }

    func put<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let request = try await makeRequest(path: path, method: "PUT", body: body)
        return try await send(request)
    }

    func delete<T: Decodable>(path: String) async throws -> T {
        let request = try await makeRequest(path: path, method: "DELETE", body: nil as EmptyBody?)
        return try await send(request)
    }

    func delete<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let request = try await makeRequest(path: path, method: "DELETE", body: body)
        return try await send(request)
    }

    /// Store a session JWT from OAuth deep link into the shared cookie jar.
    func setSessionToken(_ token: String) {
        guard let host = APIConfig.baseURL.host else { return }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: host,
            .path: "/",
            .name: APIConfig.sessionCookieName,
            .value: token,
        ]
        if APIConfig.baseURL.scheme == "https" {
            properties[.secure] = "TRUE"
        }
        if let cookie = HTTPCookie(properties: properties) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// Drop auth cookies locally (session + CSRF). Used when the jar is out of sync with `AuthStore`.
    func clearAuthCookies() {
        let storage = HTTPCookieStorage.shared
        let names: Set<String> = [APIConfig.sessionCookieName, APIConfig.csrfCookieName]
        let host = APIConfig.baseURL.host?.lowercased()
        let candidates = (storage.cookies ?? []) + (storage.cookies(for: APIConfig.baseURL) ?? [])
        var seen = Set<ObjectIdentifier>()
        for cookie in candidates {
            let id = ObjectIdentifier(cookie)
            guard seen.insert(id).inserted else { continue }
            let nameMatch = names.contains(cookie.name)
            let hostMatch = host.map { cookie.domain.lowercased().contains($0) } ?? true
            if nameMatch || (hostMatch && cookie.name.lowercased().contains("pickleball")) {
                storage.deleteCookie(cookie)
            }
        }
    }

    func uploadMultipart<T: Decodable>(
        path: String,
        method: String = "POST",
        fields: [String: String],
        fileField: String? = nil,
        fileName: String = "upload.bin",
        mimeType: String = "application/octet-stream",
        fileData: Data? = nil,
        files: [(field: String, fileName: String, mimeType: String, data: Data)] = []
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let csrf = try await ensureCSRFToken()
        request.setValue(csrf, forHTTPHeaderField: APIConfig.csrfHeaderName)

        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        var uploads = files
        if let fileField, let fileData, !fileData.isEmpty {
            uploads.append((fileField, fileName, mimeType, fileData))
        }
        for file in uploads where !file.data.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append(
                "Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.fileName)\"\r\n"
            )
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        return try await send(request)
    }

    // MARK: - Private

    private struct EmptyBody: Encodable {}

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let mutating = ["POST", "PUT", "PATCH", "DELETE"].contains(method.uppercased())
        if mutating {
            let csrf = try await ensureCSRFToken()
            request.setValue(csrf, forHTTPHeaderField: APIConfig.csrfHeaderName)
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func ensureCSRFToken() async throws -> String {
        if let existing = csrfTokenFromCookieJar() {
            return existing
        }

        guard let url = URL(string: "/api/auth/me", relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }
        var bootstrap = URLRequest(url: url)
        bootstrap.httpMethod = "GET"
        bootstrap.setValue("application/json", forHTTPHeaderField: "Accept")
        _ = try await session.data(for: bootstrap)

        guard let token = csrfTokenFromCookieJar() else {
            throw APIError.missingCSRF
        }
        return token
    }

    private func csrfTokenFromCookieJar() -> String? {
        let value = HTTPCookieStorage.shared
            .cookies(for: APIConfig.baseURL)?
            .first(where: { $0.name == APIConfig.csrfCookieName })?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error.localizedDescription)
            }
        }

        let body = try? decoder.decode(AuthErrorBody.self, from: data)
        let message = body?.error.flatMap { $0.isEmpty ? nil : $0 }
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        throw APIError.http(status: http.statusCode, message: message, code: body?.code)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

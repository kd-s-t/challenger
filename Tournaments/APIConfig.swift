//
//  APIConfig.swift
//  x-court
//

import Foundation

enum APIConfig {
    /// Debug: local web (`apps/web` on 3006). Release / App Store: production.
#if DEBUG
    /// Prefer IPv4 loopback. `localhost` can hang on simulator (::1 vs IPv4).
    static let baseURL = URL(string: "http://127.0.0.1:3006")!
#else
    static let baseURL = URL(string: "https://xcourtcebu.com")!
#endif

    static let csrfCookieName = "pickleball_csrf"
    static let csrfHeaderName = "x-csrf-token"
    static let sessionCookieName = "pickleball_session"

    /// Web `isLocalRuntime` — 3D venue maps show only while pointing at local.
    static var isLocalRuntime: Bool {
#if DEBUG
        return true
#else
        let host = (baseURL.host ?? "").lowercased()
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "0.0.0.0"
#endif
    }

    /// Home live map + About venue map (hidden in prod builds).
    static var showsVenueMap: Bool { isLocalRuntime }

    /// Resolve site-relative asset paths (partner logos) against the API host.
    static func mediaURL(from pathOrURL: String) -> URL? {
        let trimmed = pathOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        let path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}

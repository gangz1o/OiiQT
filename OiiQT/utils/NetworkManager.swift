//
//  NetworkManager.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/13.
//

import Foundation

class NetworkManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = NetworkManager(allowInsecureSSL: false)

    let allowInsecureSSL: Bool
    let preservesBearerAuthorization: Bool

    init(allowInsecureSSL: Bool = false, preservesBearerAuthorization: Bool = false) {
        self.allowInsecureSSL = allowInsecureSSL
        self.preservesBearerAuthorization = preservesBearerAuthorization
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var redirected = request
        if preservesBearerAuthorization,
           let original = task.originalRequest,
           let authorization = original.value(forHTTPHeaderField: "Authorization"),
           authorization.hasPrefix("Bearer "),
           let originalURL = original.url, let sourceURL = response.url, let targetURL = request.url,
           Self.hasSameOrigin(originalURL, sourceURL), Self.hasSameOrigin(originalURL, targetURL) {
            // URLSession strips Authorization even on same-origin redirects.
            redirected.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }

    private static func hasSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsPort = lhs.port ?? (lhs.scheme == "https" ? 443 : 80)
        let rhsPort = rhs.port ?? (rhs.scheme == "https" ? 443 : 80)
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && lhsPort == rhsPort
    }

    // MARK: - URLSessionDelegate

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        // SSL Certificate Handling
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            // Only allow if explicitly enabled
            if allowInsecureSSL, let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // Default handling for other auth methods
        completionHandler(.performDefaultHandling, nil)
    }
}

//
//  NetworkManager.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import Foundation

class NetworkManager: NSObject, URLSessionDelegate {
    static let shared = NetworkManager(allowInsecureSSL: false)

    let allowInsecureSSL: Bool

    init(allowInsecureSSL: Bool = false) {
        self.allowInsecureSSL = allowInsecureSSL
        super.init()
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

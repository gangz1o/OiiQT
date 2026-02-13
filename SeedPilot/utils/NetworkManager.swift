//
//  NetworkManager.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import Foundation

class NetworkManager: NSObject, URLSessionDelegate {
    static let shared = NetworkManager()
    
    // Prevent external initialization
    private override init() {}
    
    // MARK: - URLSessionDelegate
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        // SSL Certificate Handling
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            // Allow self-signed certificates (e.g. for user's NAS)
            if let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        
        // Default handling for other auth methods
        completionHandler(.performDefaultHandling, nil)
    }
}

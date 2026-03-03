//
//  TrackerNameManager.swift
//  SeedPilot
//  "tracker.hhanclub.net": "憨憨",        
//  "audiences.me": "观众",        
//  "hdfans.org": "红豆饭",        
//  Created by Codex on 2026/2/25.
//

import Foundation

enum TrackerNameManager {
    nonisolated private static let knownTrackerNames: [String: String] = [
        "tracker.areyouok.tech": "AreYouOK",
    ]

    nonisolated private static let ignoredPrefixes: Set<String> = [
        "tracker",
        "torrent",
        "www",
        "ipv4",
        "ipv6"
    ]

    nonisolated static func displayName(for rawTracker: String) -> String {
        displayName(for: rawTracker, aliasMap: [:])
    }

    nonisolated static func displayName(for rawTracker: String, aliasMap: [String: String]) -> String {
        let host = normalizedHost(from: rawTracker)
        guard !host.isEmpty else { return "--" }

        if let alias = aliasDisplayName(forHost: host, aliasMap: aliasMap) {
            return alias
        }

        if let preset = knownTrackerNames[host] {
            return preset
        }

        return inferredName(fromHost: host)
    }

    nonisolated static func normalizedHost(from rawTracker: String) -> String {
        let candidate = rawTracker
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        guard !candidate.isEmpty else { return "" }

        if let url = URL(string: candidate), let host = url.host, !host.isEmpty {
            return stripPortIfNeeded(host.lowercased())
        }

        var value = candidate
        if let schemeRange = value.range(of: "://") {
            value = String(value[schemeRange.upperBound...])
        }

        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }

        return stripPortIfNeeded(value.lowercased())
    }

    nonisolated private static func aliasDisplayName(
        forHost host: String,
        aliasMap: [String: String]
    ) -> String? {
        guard let alias = aliasMap[host]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !alias.isEmpty else {
            return nil
        }
        return alias
    }

    nonisolated private static func stripPortIfNeeded(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        if !value.hasPrefix("["),
           let colon = value.lastIndex(of: ":"),
           colon != value.startIndex {
            let hostPart = String(value[..<colon])
            let portPart = String(value[value.index(after: colon)...])
            if Int(portPart) != nil {
                value = hostPart
            }
        }

        return value
    }

    nonisolated private static func inferredName(fromHost host: String) -> String {
        var labels = host
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }

        while let first = labels.first, ignoredPrefixes.contains(first) {
            labels.removeFirst()
        }

        guard !labels.isEmpty else { return "--" }

        let candidate: String
        if labels.count == 1 {
            candidate = labels[0]
        } else if labels.count >= 3,
                  ["co", "com", "net", "org", "gov", "edu", "ac"].contains(labels[labels.count - 2]) {
            candidate = labels[labels.count - 3]
        } else {
            candidate = labels[labels.count - 2]
        }

        return prettifiedLabel(candidate.isEmpty ? labels[0] : candidate)
    }

    nonisolated private static func prettifiedLabel(_ label: String) -> String {
        guard !label.isEmpty else { return "--" }
        guard label.unicodeScalars.contains(where: CharacterSet.letters.contains) else {
            return label
        }

        let lowercased = label.lowercased()
        guard let first = lowercased.first else { return label }
        return String(first).uppercased() + lowercased.dropFirst()
    }
}

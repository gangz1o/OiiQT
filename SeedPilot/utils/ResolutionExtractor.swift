//
//  ResolutionExtractor.swift
//  SeedPilot
//

import SwiftUI

struct ResolutionExtractor {
    static func extractResolution(from title: String) -> (text: String, color: Color)? {
        let lowercasedTitle = title.lowercased()

        if lowercasedTitle.contains("2160p") || lowercasedTitle.contains("4k") || lowercasedTitle.contains("uhd") {
            return ("4K", .purple)
        } else if lowercasedTitle.contains("1080p") || lowercasedTitle.contains("1080i") {
            return ("1080p", .blue)
        } else if lowercasedTitle.contains("720p") {
            return ("720p", .green)
        }

        return nil
    }
}

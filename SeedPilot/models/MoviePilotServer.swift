import Foundation

nonisolated struct MoviePilotServerConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var baseURLString: String

    init(id: UUID = UUID(), name: String, baseURLString: String) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
    }
}

nonisolated struct MoviePilotCurrentUser: Decodable, Sendable {
    let id: Int?
    let name: String
}

nonisolated struct MoviePilotAPIErrorPayload: Decodable, Sendable {
    let detail: String?
}

nonisolated enum MoviePilotURLNormalizer {
    static func normalize(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }

        let normalizedScheme = components.scheme?.lowercased()
        guard let normalizedScheme, normalizedScheme == "http" || normalizedScheme == "https" else {
            return nil
        }
        guard components.host?.isEmpty == false else { return nil }

        components.scheme = normalizedScheme
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        components.percentEncodedPath = normalizedBasePath(from: components.percentEncodedPath)

        return components.url?.absoluteString
    }

    private static func normalizedBasePath(from rawPath: String) -> String {
        var trimmedPath = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmedPath.hasSuffix("api/v1") {
            trimmedPath.removeLast("api/v1".count)
            trimmedPath = trimmedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard !trimmedPath.isEmpty else { return "" }
        return "/" + trimmedPath
    }
}

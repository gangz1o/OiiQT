import Foundation

enum DoubanImageURLNormalizer {
    static func normalize(_ rawPath: String) -> String {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return rawPath }

        let lowercasedPath = trimmedPath.lowercased()
        if lowercasedPath.hasPrefix("http://") || lowercasedPath.hasPrefix("https://") {
            return trimmedPath
        }

        if trimmedPath.hasPrefix("//") {
            return "https:\(trimmedPath)"
        }

        if lowercasedPath.contains("doubanio.com") {
            let normalizedPath = trimmedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "https://\(normalizedPath)"
        }

        if trimmedPath.hasPrefix("/") {
            return "https://img9.doubanio.com\(trimmedPath)"
        }

        return "https://img9.doubanio.com/\(trimmedPath)"
    }
}

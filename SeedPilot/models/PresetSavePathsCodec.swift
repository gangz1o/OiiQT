import Foundation

enum PresetSavePathsCodec {
    static func decode(_ rawValue: String) -> [String] {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return normalize(decoded)
    }

    static func encode(_ paths: [String]) -> String {
        let normalized = normalize(paths)
        guard let data = try? JSONEncoder().encode(normalized),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }

    static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}

import Foundation

nonisolated enum MoviePilotResponseDecoder {
    static func responseData(_ data: Data, response: HTTPURLResponse, unwrap: Bool = true) throws -> Data {
        let object = try? JSONSerialization.jsonObject(with: data)
        let envelope = object as? [String: Any]
        let message = (envelope?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (envelope?["detail"] as? String)

        guard (200..<300).contains(response.statusCode) else {
            throw NSError(
                domain: "MoviePilotAPI", code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)]
            )
        }
        if envelope?["success"] as? Bool == false {
            throw NSError(
                domain: "MoviePilotAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message ?? NSLocalizedString("MoviePilot request failed.", comment: "")]
            )
        }
        guard object != nil else { throw URLError(.cannotDecodeContentData) }
        guard unwrap else { return data }
        if envelope?["success"] is Bool, envelope?["data"] == nil {
            throw URLError(.cannotDecodeContentData)
        }
        guard let payload = envelope?["data"] else { return data }
        guard !(payload is NSNull) else { throw URLError(.cannotDecodeContentData) }
        return try JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed)
    }

    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        let decoder = JSONDecoder()
        if let response = try? decoder.decode(type, from: data) { return response }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["list", "items", "results"] {
                if let items = object[key], JSONSerialization.isValidJSONObject(items) {
                    return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: items))
                }
            }
        }
        return try decoder.decode(type, from: data)
    }

    static func shouldRetryAuthentication(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == "MoviePilotAPI" && (error.code == 401 || error.code == 403)
    }
}

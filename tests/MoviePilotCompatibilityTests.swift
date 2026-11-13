import Foundation

@main
struct MoviePilotCompatibilityTests {
    static func main() async throws {
        let root = CommandLine.arguments[1]
        let connection = MoviePilotAPIClient()
        let discovery = MoviePilotDiscoveryAPIClient()
        let details = MoviePilotMediaDetailAPIClient()
        var passed = 0

        for version in ["v2", "v3"] {
            let base = root + "/" + version
            for token in ["fixture-api-key", "fixture-access-token", "fixture-query-key", "fixture-query-token"] {
                let user = try await connection.fetchCurrentUser(baseURLString: base + "/api/v1/", token: token)
                precondition(user.name == "Fixture User" && user.id == 7)
                passed += 1
            }
            let token = "fixture-api-key"
            let sources = try await discovery.request(MPRecommendSourceListDTO.self, baseURLString: base, token: token, route: .recommendSource)
            precondition(sources.first?.apiPath == "/api/v1/recommend/tmdb_movies")
            let media = try await discovery.requestMediaList(baseURLString: base, token: token, route: .tmdbMovies())
            precondition(media.first?.title == "Fixture Movie" && media.first?.source == "tmdb")
            let search = try await discovery.requestMediaSearchResults(baseURLString: base, token: token, title: "Fixture")
            precondition(search.first?.mediaID == "123")
            passed += 3

            let detail = try await details.requestMediaDetail(baseURLString: base, token: token, mediaID: "tmdb:123", typeName: "电影", title: nil, year: nil)
            precondition(detail.title == "Fixture Movie" && detail.mediaID == "123")
            let credits = try await details.requestCredits(baseURLString: base, token: token, mediaID: "tmdb:123", typeName: "电影")
            precondition(!credits.isEmpty)
            let torrents = try await details.requestSearchResults(baseURLString: base, token: token, mediaID: "tmdb:123", mediaType: "电影", title: nil, year: nil, season: nil)
            precondition(torrents.count == 1)
            let raw = try JSONSerialization.jsonObject(with: torrents[0].rawTorrentInfoJSON) as! [String: Any]
            precondition(raw["future_field"] as? String == "preserve-me")
            let clients = try await details.requestDownloadClients(baseURLString: base, token: token)
            precondition(clients.first?.name == "Fixture Downloader")
            let added = try await details.requestDownloadAdd(baseURLString: base, token: token, torrentInfoRawJSON: torrents[0].rawTorrentInfoJSON, downloader: "Fixture Downloader", savePath: nil)
            precondition(added.success)
            passed += 5
        }

        for scenario in ["business-failure", "html", "null-user", "unauthorized"] {
            do {
                _ = try await connection.fetchCurrentUser(baseURLString: root + "/" + scenario, token: "fixture-api-key")
                preconditionFailure("\(scenario) must not report a connected user")
            } catch {
                if scenario == "business-failure" {
                    precondition(error.localizedDescription == "Fixture failure")
                }
                passed += 1
            }
        }
        for scenario in ["failed-detail", "null-detail"] {
            do {
                _ = try await details.requestMediaDetail(baseURLString: root + "/" + scenario, token: "fixture-api-key", mediaID: "tmdb:123", typeName: "电影", title: nil, year: nil)
                preconditionFailure("An invalid envelope must not decode as an empty media item")
            } catch { passed += 1 }
        }
        do {
            _ = try await details.requestDownloadAdd(baseURLString: root + "/download-failure", token: "fixture-access-token", torrentInfoRawJSON: Data(#"{"title":"Fixture"}"#.utf8), downloader: nil, savePath: nil)
            preconditionFailure("A failed download must not succeed or be retried with other credentials")
        } catch {
            precondition((error as NSError).code == 500 && error.localizedDescription == "Download failed")
            passed += 1
        }
        print("Passed \(passed) MoviePilot V2/V3 compatibility checks")
    }
}

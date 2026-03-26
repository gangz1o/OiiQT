import Foundation

typealias MPMediaListDTO = [MPMediaItemDTO]
typealias MPRecommendSourceListDTO = [MPRecommendSourceDTO]

nonisolated struct MoviePilotResponseEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool?
    let message: String?
    let data: Payload?
}

nonisolated struct MPRecommendSourceDTO: Decodable, Sendable, Equatable {
    let name: String
    let apiPath: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case name
        case apiPath = "api_path"
        case type
    }
}

nonisolated struct MPMediaItemDTO: Decodable, Sendable, Equatable {
    let source: String?
    let type: String?
    let title: String?
    let name: String?
    let enTitle: String?
    let titleYear: String?
    let year: String?
    let season: Int?
    let tmdbID: Int?
    let imdbID: String?
    let tvdbID: String?
    let doubanID: String?
    let bangumiID: Int?
    let collectionID: Int?
    let mediaIDPrefix: String?
    let mediaID: String?
    let originalLanguage: String?
    let originalTitle: String?
    let originalName: String?
    let releaseDate: String?
    let firstAirDate: String?
    let backdropPath: String?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let rating: MPMediaRatingDTO?
    let overview: String?
    let category: String?
    let detailLink: String?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case source
        case type
        case title
        case name
        case enTitle = "en_title"
        case titleYear = "title_year"
        case year
        case season
        case tmdbID = "tmdb_id"
        case imdbID = "imdb_id"
        case tvdbID = "tvdb_id"
        case doubanID = "douban_id"
        case bangumiID = "bangumi_id"
        case collectionID = "collection_id"
        case mediaIDPrefix = "mediaid_prefix"
        case mediaID = "media_id"
        case originalLanguage = "original_language"
        case originalTitle = "original_title"
        case originalName = "original_name"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case backdropPath = "backdrop_path"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case rating
        case overview
        case category
        case detailLink = "detail_link"
        case popularity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        source = container.decodeLossyString(forKey: .source)
        type = container.decodeLossyString(forKey: .type)
        title = container.decodeLossyString(forKey: .title)
        name = container.decodeLossyString(forKey: .name)
        enTitle = container.decodeLossyString(forKey: .enTitle)
        titleYear = container.decodeLossyString(forKey: .titleYear)
        year = container.decodeLossyString(forKey: .year)
        season = container.decodeLossyInt(forKey: .season)
        tmdbID = container.decodeLossyInt(forKey: .tmdbID)
        imdbID = container.decodeLossyString(forKey: .imdbID)
        tvdbID = container.decodeLossyString(forKey: .tvdbID)
        doubanID = container.decodeLossyString(forKey: .doubanID)
        bangumiID = container.decodeLossyInt(forKey: .bangumiID)
        collectionID = container.decodeLossyInt(forKey: .collectionID)
        mediaIDPrefix = container.decodeLossyString(forKey: .mediaIDPrefix)
        mediaID = container.decodeLossyString(forKey: .mediaID)
        originalLanguage = container.decodeLossyString(forKey: .originalLanguage)
        originalTitle = container.decodeLossyString(forKey: .originalTitle)
        originalName = container.decodeLossyString(forKey: .originalName)
        releaseDate = container.decodeLossyString(forKey: .releaseDate)
        firstAirDate = container.decodeLossyString(forKey: .firstAirDate)
        backdropPath = container.decodeLossyString(forKey: .backdropPath)
        posterPath = container.decodeLossyString(forKey: .posterPath)
        voteAverage = container.decodeLossyDouble(forKey: .voteAverage)
        voteCount = container.decodeLossyInt(forKey: .voteCount)
        rating = try container.decodeIfPresent(MPMediaRatingDTO.self, forKey: .rating)
        overview = container.decodeLossyString(forKey: .overview)
        category = container.decodeLossyString(forKey: .category)
        detailLink = container.decodeLossyString(forKey: .detailLink)
        popularity = container.decodeLossyDouble(forKey: .popularity)
    }
}

nonisolated struct MPMediaRatingDTO: Decodable, Sendable, Equatable {
    let value: Double?

    private enum CodingKeys: String, CodingKey {
        case value
        case average
        case score
    }

    init(value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer() {
            if singleValueContainer.decodeNil() {
                self.value = nil
                return
            }

            if let doubleValue = try? singleValueContainer.decode(Double.self) {
                self.value = doubleValue
                return
            }

            if let intValue = try? singleValueContainer.decode(Int.self) {
                self.value = Double(intValue)
                return
            }

            if let stringValue = try? singleValueContainer.decode(String.self) {
                self.value = Double(stringValue)
                return
            }
        }

        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try keyedContainer.decodeIfPresent(Double.self, forKey: .value) {
            self.value = value
            return
        }

        if let value = try keyedContainer.decodeIfPresent(Double.self, forKey: .average) {
            self.value = value
            return
        }

        if let value = try keyedContainer.decodeIfPresent(Double.self, forKey: .score) {
            self.value = value
            return
        }

        if let stringValue = try keyedContainer.decodeIfPresent(String.self, forKey: .value) {
            self.value = Double(stringValue)
            return
        }

        if let stringValue = try keyedContainer.decodeIfPresent(String.self, forKey: .average) {
            self.value = Double(stringValue)
            return
        }

        if let stringValue = try keyedContainer.decodeIfPresent(String.self, forKey: .score) {
            self.value = Double(stringValue)
            return
        }

        self.value = nil
    }
}

extension KeyedDecodingContainer {
    nonisolated func decodeLossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }

        return nil
    }

    nonisolated func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }

        return nil
    }

    nonisolated func decodeLossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }

        return nil
    }
}

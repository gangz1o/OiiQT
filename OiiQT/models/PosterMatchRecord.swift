import Foundation
import SwiftData

@Model
final class PosterMatchRecord {
    @Attribute(.unique) var hashString: String
    var titleCacheKey: String
    var posterURLString: String?
    var providerRawValue: String
    var lastMatchedTime: Date

    init(
        hashString: String,
        titleCacheKey: String,
        posterURLString: String?,
        providerRawValue: String,
        lastMatchedTime: Date = Date()
    ) {
        self.hashString = hashString
        self.titleCacheKey = titleCacheKey
        self.posterURLString = posterURLString
        self.providerRawValue = providerRawValue
        self.lastMatchedTime = lastMatchedTime
    }
}

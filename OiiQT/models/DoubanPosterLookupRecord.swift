import Foundation
import SwiftData

@Model
final class DoubanPosterLookupRecord {
    @Attribute(.unique) var lookupKey: String
    var titleCacheKey: String
    var queryValue: String
    var targetYear: String?
    var mediaType: String
    var posterURLString: String?
    var subjectID: String?
    var outcomeRawValue: String
    var failureReason: String?
    var validUntil: Date
    var lastUpdatedAt: Date

    init(
        lookupKey: String,
        titleCacheKey: String,
        queryValue: String,
        targetYear: String?,
        mediaType: String,
        posterURLString: String?,
        subjectID: String?,
        outcomeRawValue: String,
        failureReason: String?,
        validUntil: Date,
        lastUpdatedAt: Date = Date()
    ) {
        self.lookupKey = lookupKey
        self.titleCacheKey = titleCacheKey
        self.queryValue = queryValue
        self.targetYear = targetYear
        self.mediaType = mediaType
        self.posterURLString = posterURLString
        self.subjectID = subjectID
        self.outcomeRawValue = outcomeRawValue
        self.failureReason = failureReason
        self.validUntil = validUntil
        self.lastUpdatedAt = lastUpdatedAt
    }
}

import Foundation

struct RateLimitSettings: Equatable {
    // Global limits (KB/s in UI layer)
    var globalDownloadEnabled: Bool = false
    var globalDownloadKBps: Int = 0
    var globalUploadEnabled: Bool = false
    var globalUploadKBps: Int = 0

    // Alternative limits (KB/s in UI layer)
    var alternativeEnabled: Bool = false
    var alternativeDownloadEnabled: Bool = false
    var alternativeDownloadKBps: Int = 0
    var alternativeUploadEnabled: Bool = false
    var alternativeUploadKBps: Int = 0

    // Scheduled alternative limits
    var scheduleEnabled: Bool = false
    var scheduleStartMinutes: Int = 0
    var scheduleEndMinutes: Int = 0
    // 0...6 => Sun...Sat
    var scheduleWeekdays: Set<Int> = Set(0...6)

    func normalized() -> RateLimitSettings {
        var copy = self
        copy.globalDownloadKBps = max(copy.globalDownloadKBps, 0)
        copy.globalUploadKBps = max(copy.globalUploadKBps, 0)
        copy.alternativeDownloadKBps = max(copy.alternativeDownloadKBps, 0)
        copy.alternativeUploadKBps = max(copy.alternativeUploadKBps, 0)
        copy.scheduleStartMinutes = RateLimitSettings.clampedMinute(copy.scheduleStartMinutes)
        copy.scheduleEndMinutes = RateLimitSettings.clampedMinute(copy.scheduleEndMinutes)
        copy.scheduleWeekdays = Set(copy.scheduleWeekdays.filter { (0...6).contains($0) })
        if copy.scheduleWeekdays.isEmpty {
            copy.scheduleWeekdays = Set(0...6)
        }
        if !copy.alternativeEnabled {
            copy.scheduleEnabled = false
        }
        return copy
    }

    static func clampedMinute(_ value: Int) -> Int {
        max(0, min(value, 1439))
    }
}

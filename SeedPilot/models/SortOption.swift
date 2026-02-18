//
//  SortOption.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case dateAdded = "添加时间"
    case name = "名称"
    case downloadSpeed = "下载速度"
    case uploadSpeed = "上传速度"
    case size = "大小"
    case progress = "进度"

    var id: String { rawValue }

    var localizedDisplayName: String {
        switch self {
        case .dateAdded:
            return LanguageManager.shared.localized("Date Added")
        case .name:
            return LanguageManager.shared.localized("Name")
        case .downloadSpeed:
            return LanguageManager.shared.localized("Download Speed")
        case .uploadSpeed:
            return LanguageManager.shared.localized("Upload Speed")
        case .size:
            return LanguageManager.shared.localized("Size")
        case .progress:
            return LanguageManager.shared.localized("Progress")
        }
    }
}

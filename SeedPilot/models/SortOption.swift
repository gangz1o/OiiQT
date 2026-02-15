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
}

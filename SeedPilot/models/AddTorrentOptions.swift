//
//  AddTorrentOptions.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import Foundation

struct AddTorrentOptions {
    var savePath: String = ""
    var category: String = ""
    var tags: [String] = []
    var isPaused: Bool = false
    var skipHashCheck: Bool = false
    var isSequential: Bool = false
    var isFirstLastPiecePriority: Bool = false
}

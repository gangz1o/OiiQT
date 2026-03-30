//
//  Item.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/13.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

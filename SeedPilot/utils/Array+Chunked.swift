//
//  Array+Chunked.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/3/3.
//

import Foundation

extension Array {
    /// Split array into chunks of the given size.
    /// Example: [1,2,3,4,5].chunked(into: 2) → [[1,2],[3,4],[5]]
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

//
//  Item.swift
//  BabyMont
//
//  Created by Christopher Appiah-Thompson  on 19/7/2026.
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

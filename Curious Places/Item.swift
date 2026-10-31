//
//  Item.swift
//  Curious Places
//
//  Created by Nick Jewell on 31/10/2026.
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

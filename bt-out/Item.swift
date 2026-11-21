//
//  Item.swift
//  bt-out
//
//  Created by Matthijs on 21/11/2026.
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

//
//  Item.swift
//  KKT
//
//  Created by Kevin Tao on 2026-09-20.
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

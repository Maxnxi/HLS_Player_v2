//
//  Item.swift
//  HLS_Player_v2
//
//  Created by Maksim Ponomarev on 10/9/24.
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

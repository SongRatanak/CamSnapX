//
//  CaptureHistoryItem.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import Foundation

struct CaptureHistoryItem: Identifiable, Codable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date

    init(fileURL: URL, createdAt: Date = Date()) {
        self.id = UUID()
        self.fileURL = fileURL
        self.createdAt = createdAt
    }
}

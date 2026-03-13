//
//  CaptureHistoryStore.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import Combine
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

final class CaptureHistoryStore: ObservableObject {
    static let shared = CaptureHistoryStore()

    @Published private(set) var items: [CaptureHistoryItem] = []

    private let storageKey = "CaptureHistoryStore.items"
    private let maximumItems = 50

    private init() {
        load()
    }

    func add(_ fileURL: URL) {
        var updated = items
        updated.insert(CaptureHistoryItem(fileURL: fileURL), at: 0)
        if updated.count > maximumItems {
            updated = Array(updated.prefix(maximumItems))
        }
        items = updated
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([CaptureHistoryItem].self, from: data) {
            items = decoded
        }
    }
}


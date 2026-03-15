//
//  CaptureHistoryStore.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import Combine
import Foundation
import AppKit

final class CaptureHistoryStore: ObservableObject {
    static let shared = CaptureHistoryStore()

    @Published private(set) var items: [CaptureHistoryItem] = []
    @Published var retentionDays: Int? = nil {
        didSet {
            if let retentionDays {
                userDefaults.set(retentionDays, forKey: retentionKey)
            } else {
                userDefaults.removeObject(forKey: retentionKey)
            }
            applyRetention()
        }
    }

    private let storageKey = "CaptureHistoryStore.items"
    private let retentionKey = "CaptureHistoryStore.retentionDays"
    private let maximumItems = 50
    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let calendar = Calendar.current

    private init() {
        load()
    }

    func add(_ fileURL: URL) {
        // Remove any existing entry for the same file to avoid duplicates
        var updated = items.filter { $0.fileURL != fileURL }
        updated.insert(CaptureHistoryItem(fileURL: fileURL), at: 0)
        if updated.count > maximumItems {
            updated = Array(updated.prefix(maximumItems))
        }
        items = updated
        applyRetention()
        save()
    }

    func clearWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Delete Capture History"
        alert.informativeText = "This will permanently delete all files from your history. Are you sure?"
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.buttons.first?.contentTintColor = .systemRed

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            clear(deleteFiles: true)
        }
    }

    func clear(deleteFiles: Bool) {
        if deleteFiles {
            items.forEach { item in
                try? fileManager.removeItem(at: item.fileURL)
            }
        }
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
        retentionDays = userDefaults.object(forKey: retentionKey) as? Int
        applyRetention()
        pruneInvalidFiles()
    }

    /// Remove history entries whose files no longer exist on disk.
    private func pruneInvalidFiles() {
        let before = items.count
        items = items.filter { fileManager.fileExists(atPath: $0.fileURL.path) }
        if items.count != before {
            save()
        }
    }

    private func applyRetention() {
        guard let retentionDays else { return }
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let retained = items.filter { $0.createdAt >= cutoff }
        let removed = items.filter { $0.createdAt < cutoff }
        if retained.count != items.count {
            removed.forEach { item in
                try? fileManager.removeItem(at: item.fileURL)
            }
            items = retained
        }
    }
}

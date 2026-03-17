//
//  ShortcutSettingsViewModel.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import Combine
import SwiftUI

final class ShortcutSettingsViewModel: ObservableObject {
    @Published var recordingAction: ShortcutAction? = nil
    @Published var isAccessibilityTrusted = ShortcutManager.shared.isAccessibilityTrusted()

    @AppStorage("shortcut.scope") var shortcutScopeRaw = ShortcutScope.appOnly.rawValue

    private var recordingMonitor: Any?

    func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return nil }
            if let shortcut = ShortcutKey(event: event)?.displayString {
                self.saveShortcut(shortcut, for: action)
            }
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        recordingAction = nil
    }

    func storedShortcut(for action: ShortcutAction) -> String? {
        UserDefaults.standard.string(forKey: action.userDefaultsKey)
    }

    func updateScope() {
        ShortcutManager.shared.requestAccessibilityIfNeeded()
        ShortcutManager.shared.updateMonitoring()
        isAccessibilityTrusted = ShortcutManager.shared.isAccessibilityTrusted()
    }

    func refreshAccessibility() {
        isAccessibilityTrusted = ShortcutManager.shared.isAccessibilityTrusted()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func saveShortcut(_ value: String, for action: ShortcutAction) {
        UserDefaults.standard.set(value, forKey: action.userDefaultsKey)
    }
}

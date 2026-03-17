//
//  ShortcutManager.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import ApplicationServices

enum ShortcutAction: String, CaseIterable {
    case allInOne
    case toggleDesktopIcons
    case openCaptureHistory
    case restoreLastCapture
    case captureArea
    case capturePreviousArea
    case captureFullscreen
    case captureWindow
    case selfTimer
    case captureAreaCopy
    case captureAreaSave

    var label: String {
        switch self {
        case .allInOne: return "All-In-One"
        case .toggleDesktopIcons: return "Toggle Desktop Icons"
        case .openCaptureHistory: return "Open Capture History"
        case .restoreLastCapture: return "Restore Last Capture"
        case .captureArea: return "Capture Area"
        case .capturePreviousArea: return "Capture Previous Area"
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureWindow: return "Capture Window"
        case .selfTimer: return "Self-Timer"
        case .captureAreaCopy: return "Capture Area & Copy to Clipboard"
        case .captureAreaSave: return "Capture Area & Save"
        }
    }

    var userDefaultsKey: String {
        "shortcut.\(rawValue)"
    }
}

struct ShortcutKey {
    let displayString: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.shift) || flags.contains(.control)
        guard hasModifier else { return nil }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }

        var parts: [String] = []
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.control) { parts.append("⌃") }
        parts.append(key)

        displayString = parts.joined()
    }
}

final class ShortcutManager {
    static let shared = ShortcutManager()

    private var monitor: Any?
    private var globalMonitor: Any?

    private init() {}

    func startMonitoring() {
        updateMonitoring()
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    func updateMonitoring() {
        stopMonitoring()
        switch shortcutScope {
        case .appOnly:
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        case .global:
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handle(event)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }
    }

    private func handle(_ event: NSEvent) {
        guard let shortcut = ShortcutKey(event: event) else { return }

        for action in ShortcutAction.allCases {
            if UserDefaults.standard.string(forKey: action.userDefaultsKey) == shortcut.displayString {
                perform(action)
                break
            }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .allInOne:
            AllInOneOverlayController.shared.show()
        case .toggleDesktopIcons:
            break
        case .openCaptureHistory:
            CaptureHistoryPanelController.shared.show(store: CaptureHistoryStore.shared)
        case .restoreLastCapture:
            break
        case .captureArea:
            guard CaptureAreaController.shared.ensureScreenCaptureAccess() else { return }
            CaptureAreaController.shared.startCapture()
        case .capturePreviousArea:
            guard CaptureAreaController.shared.ensureScreenCaptureAccess() else { return }
            CaptureAreaController.shared.capturePreviousArea()
        case .captureFullscreen:
            guard CaptureAreaController.shared.ensureScreenCaptureAccess() else { return }
            CaptureAreaController.shared.captureFullScreen()
        case .captureWindow:
            guard CaptureAreaController.shared.ensureScreenCaptureAccess() else { return }
            CaptureAreaController.shared.captureWindow()
        case .selfTimer:
            break
        case .captureAreaCopy:
            guard CaptureAreaController.shared.ensureScreenCaptureAccess() else { return }
            CaptureAreaController.shared.startCapture()
        case .captureAreaSave:
            guard CaptureAreaController.shared.ensureScreenCaptureAccess() else { return }
            CaptureAreaController.shared.startCapture()
        }
    }
}

enum ShortcutScope: String, CaseIterable {
    case appOnly
    case global
}

extension ShortcutManager {
    var shortcutScope: ShortcutScope {
        let raw = UserDefaults.standard.string(forKey: "shortcut.scope") ?? ShortcutScope.appOnly.rawValue
        return ShortcutScope(rawValue: raw) ?? .appOnly
    }

    func requestAccessibilityIfNeeded() {
        guard shortcutScope == .global else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

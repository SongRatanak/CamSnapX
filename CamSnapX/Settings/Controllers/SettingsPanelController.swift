//
//  SettingsPanelController.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import SwiftUI

final class SettingsPanelController: NSObject, NSWindowDelegate {
    static let shared = SettingsPanelController()

    private var window: NSWindow?
    private let windowSize = NSSize(width: 520, height: 460)
    private var escMonitor: Any?
    private let viewModel = SettingsPanelViewModel()

    func show(tab: SettingsTab = .general) {
        viewModel.selectedTab = tab

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsPanelView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "CamSnapX Settings"

        window.contentView = hostingView
        window.setContentSize(windowSize)
        window.center()

        // Show in Dock
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()

        self.window = window
    }

    func hide() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        removeEscMonitor()
    }

    func windowWillMiniaturize(_ notification: Notification) {
        // Keep Dock icon visible while minimized
    }

    // MARK: - Event Monitors

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}

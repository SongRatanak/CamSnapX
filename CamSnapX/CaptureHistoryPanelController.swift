//
//  CaptureHistoryPanelController.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import QuartzCore
import SwiftUI

final class CaptureHistoryPanelController: NSObject, NSWindowDelegate {
    static let shared = CaptureHistoryPanelController()

    private var panel: NSPanel?
    private let baseSize = NSSize(width: 1200, height: 240)
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func hide() {
        guard let panel else { return }
        hidePanel(panel: panel)
        removeEventMonitors()
    }

    func show(store: CaptureHistoryStore, screen: NSScreen? = nil) {
        let resolvedScreen = screen ?? screenForMouse()
        if let panel {
            showPanel(panel: panel, on: resolvedScreen ?? NSScreen.main)
            installEventMonitors()
            return
        }

        let contentView = CaptureHistoryPanelView(store: store)
        let hostingView = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: baseSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.delegate = self

        panel.contentView = hostingView

        installEventMonitors()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak panel] in
            guard let panel else { return }
            let screen = resolvedScreen ?? self?.screenForMouse() ?? NSScreen.main
            self?.showPanel(panel: panel, on: screen)
        }

        self.panel = panel
    }

    private func position(panel: NSPanel, on screen: NSScreen?) -> (targetOrigin: NSPoint, panelSize: NSSize)? {
        guard let screen else {
            panel.setContentSize(baseSize)
            panel.center()
            return nil
        }

        let maxWidth = max(420, screen.visibleFrame.width - 24)
        let panelSize = NSSize(width: min(baseSize.width, maxWidth), height: baseSize.height)
        panel.setContentSize(panelSize)

        let topMargin: CGFloat = 6
        let centeredX = screen.visibleFrame.midX - panelSize.width / 2
        let minX = screen.visibleFrame.minX + 12
        let maxX = screen.visibleFrame.maxX - panelSize.width - 12
        let clampedX = max(minX, min(centeredX, maxX))
        let targetOrigin = NSPoint(
            x: clampedX,
            y: screen.visibleFrame.maxY - topMargin - panelSize.height
        )
        return (targetOrigin, panelSize)
    }

    private func showPanel(panel: NSPanel, on screen: NSScreen?) {
        guard let layout = position(panel: panel, on: screen) else {
            panel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        panel.setFrameOrigin(layout.targetOrigin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func screenForMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        removeEventMonitors()
    }

    private func hidePanel(panel: NSPanel) {
        panel.orderOut(nil)
    }

    private func installEventMonitors() {
        removeEventMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            let mouseLocation = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLocation) {
                self.hide()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            let mouseLocation = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLocation) {
                self.hide()
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}

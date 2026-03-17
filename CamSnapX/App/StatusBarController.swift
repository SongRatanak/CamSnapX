//
//  StatusBarController.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "CamSnapX")
            button.target = self
            button.action = #selector(togglePopover)
        }

        let contentView = ContentView()
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        let anchor = NSRect(x: button.bounds.midX - 1, y: button.bounds.minY, width: 2, height: button.bounds.height)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .maxY)
        if let window = popover.contentViewController?.view.window {
            let buttonScreen = button.window?.convertToScreen(button.frame) ?? .zero
            let targetCenterX = buttonScreen.midX
            var frame = window.frame
            frame.origin.x = targetCenterX - (frame.size.width / 2)
            if let screen = button.window?.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.size.width))
            }
            window.setFrame(frame, display: true)
            window.makeKey()
        }
    }
}

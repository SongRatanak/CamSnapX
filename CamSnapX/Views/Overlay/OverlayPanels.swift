//
//  OverlayPanels.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit

final class KeyableOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A lightweight view that draws a red dashed border rectangle.
final class SelectionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset = bounds.insetBy(dx: 2, dy: 2)

        // Red dashed border
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(inset)
    }
}

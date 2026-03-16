//
//  ScreenSelectView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit

final class ScreenSelectView: NSView {
    var onSelect: (() -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var isHovering = false
    private var buttonRect: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fill(bounds)

        let btnW: CGFloat = 280
        let btnH: CGFloat = 64
        buttonRect = CGRect(
            x: bounds.midX - btnW / 2,
            y: bounds.midY - btnH / 2,
            width: btnW,
            height: btnH
        )

        let bgColor = isHovering
            ? NSColor.white.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.85)
        let path = CGPath(roundedRect: buttonRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillPath()

        let text = "Select This Screen"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        attrStr.draw(at: CGPoint(
            x: buttonRect.midX - textSize.width / 2,
            y: buttonRect.midY - textSize.height / 2
        ))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let wasHovering = isHovering
        isHovering = buttonRect.contains(point)
        NSCursor.pointingHand.set()
        if wasHovering != isHovering {
            needsDisplay = true
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}

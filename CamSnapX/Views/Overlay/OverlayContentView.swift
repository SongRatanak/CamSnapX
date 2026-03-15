//
//  OverlayContentView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit

final class OverlayContentView: NSView {
    var screenFrame: CGRect = .zero
    var onSelectionChanged: ((CGRect) -> Void)?
    var onClose: (() -> Void)?
    var onCaptureArea: (() -> Void)?
    var onCaptureFullscreen: (() -> Void)?
    var onCaptureWindow: (() -> Void)?
    var onAnyMouseDown: (() -> Void)?

    var showsSelectionOverlay: Bool = true {
        didSet {
            needsDisplay = true
        }
    }

    var selection: CGRect = .zero {
        didSet {
            needsDisplay = true
            onSelectionChanged?(selection)
        }
    }

    private enum DragMode {
        case none
        case drawing
        case moving
        case resizeTL, resizeTR, resizeBL, resizeBR
        case resizeT, resizeB, resizeL, resizeR
    }

    private var dragMode: DragMode = .none
    private var dragStart: CGPoint = .zero
    private var dragOriginalSelection: CGRect = .zero

    private let handleSize: CGFloat = 8
    private let handleHitSize: CGFloat = 16

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let initWidth = frameRect.width * 0.55
        let initHeight = frameRect.height * 0.55
        let x = (frameRect.width - initWidth) / 2
        let y = (frameRect.height - initHeight) / 2
        selection = CGRect(x: x, y: y, width: initWidth, height: initHeight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addRect(bounds)
        if selection.width > 2, selection.height > 2 {
            ctx.addRect(selection)
        }
        ctx.drawPath(using: .eoFill)

        guard showsSelectionOverlay else { return }
        guard selection.width > 2, selection.height > 2 else { return }

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(selection.insetBy(dx: -0.75, dy: -0.75))

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)

        let s = selection
        let cornerLen: CGFloat = 20

        drawCornerL(ctx: ctx, corner: CGPoint(x: s.minX, y: s.minY), dx: 1, dy: 1, len: cornerLen)
        drawCornerL(ctx: ctx, corner: CGPoint(x: s.maxX, y: s.minY), dx: -1, dy: 1, len: cornerLen)
        drawCornerL(ctx: ctx, corner: CGPoint(x: s.minX, y: s.maxY), dx: 1, dy: -1, len: cornerLen)
        drawCornerL(ctx: ctx, corner: CGPoint(x: s.maxX, y: s.maxY), dx: -1, dy: -1, len: cornerLen)

        let midHandleW: CGFloat = 16
        let midHandleH: CGFloat = 5

        ctx.fill(CGRect(x: s.midX - midHandleW/2, y: s.minY - midHandleH/2, width: midHandleW, height: midHandleH))
        ctx.fill(CGRect(x: s.midX - midHandleW/2, y: s.maxY - midHandleH/2, width: midHandleW, height: midHandleH))
        ctx.fill(CGRect(x: s.minX - midHandleH/2, y: s.midY - midHandleW/2, width: midHandleH, height: midHandleW))
        ctx.fill(CGRect(x: s.maxX - midHandleH/2, y: s.midY - midHandleW/2, width: midHandleH, height: midHandleW))

        let sizeStr = "\(Int(selection.width)) x \(Int(selection.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: sizeStr, attributes: attrs)
        let textSize = attrStr.size()
        let labelPad: CGFloat = 4
        let labelRect = CGRect(
            x: selection.minX + 6,
            y: selection.minY + 6,
            width: textSize.width + labelPad * 2,
            height: textSize.height + labelPad
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        let labelPath = CGPath(roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(labelPath)
        ctx.fillPath()
        attrStr.draw(at: CGPoint(x: labelRect.minX + labelPad, y: labelRect.minY + labelPad / 2))
    }

    private func drawCornerL(ctx: CGContext, corner: CGPoint, dx: CGFloat, dy: CGFloat, len: CGFloat) {
        let thickness: CGFloat = 3
        ctx.setLineWidth(thickness)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineCap(.round)

        ctx.move(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x + dx * len, y: corner.y))
        ctx.strokePath()

        ctx.move(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * len))
        ctx.strokePath()
    }

    // MARK: - Hit Testing

    private func hitTestHandle(at point: CGPoint) -> DragMode {
        let s = selection
        guard s.width > 2, s.height > 2 else { return .none }

        let hh = handleHitSize

        if CGRect(x: s.minX - hh/2, y: s.minY - hh/2, width: hh, height: hh).contains(point) { return .resizeTL }
        if CGRect(x: s.maxX - hh/2, y: s.minY - hh/2, width: hh, height: hh).contains(point) { return .resizeTR }
        if CGRect(x: s.minX - hh/2, y: s.maxY - hh/2, width: hh, height: hh).contains(point) { return .resizeBL }
        if CGRect(x: s.maxX - hh/2, y: s.maxY - hh/2, width: hh, height: hh).contains(point) { return .resizeBR }

        let edgeTol: CGFloat = 6
        if abs(point.y - s.minY) < edgeTol && point.x > s.minX + hh && point.x < s.maxX - hh { return .resizeT }
        if abs(point.y - s.maxY) < edgeTol && point.x > s.minX + hh && point.x < s.maxX - hh { return .resizeB }
        if abs(point.x - s.minX) < edgeTol && point.y > s.minY + hh && point.y < s.maxY - hh { return .resizeL }
        if abs(point.x - s.maxX) < edgeTol && point.y > s.minY + hh && point.y < s.maxY - hh { return .resizeR }

        if s.contains(point) { return .moving }

        return .none
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        onAnyMouseDown?()

        let mode = hitTestHandle(at: point)
        if mode != .none {
            dragMode = mode
            dragStart = point
            dragOriginalSelection = selection
        } else {
            dragMode = .drawing
            dragStart = point
            dragOriginalSelection = selection
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clamped = clampPoint(point)

        switch dragMode {
        case .drawing:
            let x = min(dragStart.x, clamped.x)
            let y = min(dragStart.y, clamped.y)
            let w = abs(clamped.x - dragStart.x)
            let h = abs(clamped.y - dragStart.y)
            selection = CGRect(x: x, y: y, width: w, height: h)

        case .moving:
            let dx = clamped.x - dragStart.x
            let dy = clamped.y - dragStart.y
            var newRect = dragOriginalSelection.offsetBy(dx: dx, dy: dy)
            newRect.origin.x = max(0, min(newRect.origin.x, bounds.width - newRect.width))
            newRect.origin.y = max(0, min(newRect.origin.y, bounds.height - newRect.height))
            selection = newRect

        case .resizeTL:
            let newMinX = min(clamped.x, dragOriginalSelection.maxX - 10)
            let newMinY = min(clamped.y, dragOriginalSelection.maxY - 10)
            selection = CGRect(x: newMinX, y: newMinY, width: dragOriginalSelection.maxX - newMinX, height: dragOriginalSelection.maxY - newMinY)

        case .resizeTR:
            let newMaxX = max(clamped.x, dragOriginalSelection.minX + 10)
            let newMinY = min(clamped.y, dragOriginalSelection.maxY - 10)
            selection = CGRect(x: dragOriginalSelection.minX, y: newMinY, width: newMaxX - dragOriginalSelection.minX, height: dragOriginalSelection.maxY - newMinY)

        case .resizeBL:
            let newMinX = min(clamped.x, dragOriginalSelection.maxX - 10)
            let newMaxY = max(clamped.y, dragOriginalSelection.minY + 10)
            selection = CGRect(x: newMinX, y: dragOriginalSelection.minY, width: dragOriginalSelection.maxX - newMinX, height: newMaxY - dragOriginalSelection.minY)

        case .resizeBR:
            let newMaxX = max(clamped.x, dragOriginalSelection.minX + 10)
            let newMaxY = max(clamped.y, dragOriginalSelection.minY + 10)
            selection = CGRect(x: dragOriginalSelection.minX, y: dragOriginalSelection.minY, width: newMaxX - dragOriginalSelection.minX, height: newMaxY - dragOriginalSelection.minY)

        case .resizeT:
            let newMinY = min(clamped.y, dragOriginalSelection.maxY - 10)
            selection = CGRect(x: dragOriginalSelection.minX, y: newMinY, width: dragOriginalSelection.width, height: dragOriginalSelection.maxY - newMinY)

        case .resizeB:
            let newMaxY = max(clamped.y, dragOriginalSelection.minY + 10)
            selection = CGRect(x: dragOriginalSelection.minX, y: dragOriginalSelection.minY, width: dragOriginalSelection.width, height: newMaxY - dragOriginalSelection.minY)

        case .resizeL:
            let newMinX = min(clamped.x, dragOriginalSelection.maxX - 10)
            selection = CGRect(x: newMinX, y: dragOriginalSelection.minY, width: dragOriginalSelection.maxX - newMinX, height: dragOriginalSelection.height)

        case .resizeR:
            let newMaxX = max(clamped.x, dragOriginalSelection.minX + 10)
            selection = CGRect(x: dragOriginalSelection.minX, y: dragOriginalSelection.minY, width: newMaxX - dragOriginalSelection.minX, height: dragOriginalSelection.height)

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode == .drawing && selection.width < 4 && selection.height < 4 {
            selection = dragOriginalSelection
        }
        dragMode = .none
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(for: point)
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

    private func updateCursor(for point: CGPoint) {
        if !showsSelectionOverlay {
            NSCursor.arrow.set()
            return
        }
        let mode = hitTestHandle(at: point)
        switch mode {
        case .resizeTL, .resizeBR: NSCursor.crosshair.set()
        case .resizeTR, .resizeBL: NSCursor.crosshair.set()
        case .resizeT, .resizeB: NSCursor.resizeUpDown.set()
        case .resizeL, .resizeR: NSCursor.resizeLeftRight.set()
        case .moving: NSCursor.openHand.set()
        case .drawing, .none: NSCursor.crosshair.set()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onClose?()
        } else if event.keyCode == 36 { // Enter
            onCaptureArea?()
        }
    }

    private func clampPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(point.x, bounds.width)),
            y: max(0, min(point.y, bounds.height))
        )
    }
}

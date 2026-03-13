//
//  CaptureAreaOverlayView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit

protocol CaptureAreaOverlayViewDelegate: AnyObject {
    func captureAreaOverlayViewDidCancel(_ view: CaptureAreaOverlayView)
    func captureAreaOverlayView(_ view: CaptureAreaOverlayView, didFinishWith rect: CGRect)
}

final class CaptureAreaOverlayView: NSView {
    weak var delegate: CaptureAreaOverlayViewDelegate?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
            NSCursor.crosshair.set()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            NSCursor.arrow.set()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            delegate?.captureAreaOverlayViewDidCancel(self)
        case 36, 76:
            finishSelectionIfPossible()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint, let currentPoint else {
            delegate?.captureAreaOverlayViewDidCancel(self)
            return
        }

        let rect = normalizedRect(from: startPoint, to: currentPoint)
        if rect.width < 2 || rect.height < 2 {
            delegate?.captureAreaOverlayViewDidCancel(self)
            return
        }

        let screenRect = convertToScreenCoordinates(rect)
        delegate?.captureAreaOverlayView(self, didFinishWith: screenRect)
    }

    override func mouseMoved(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let startPoint, let currentPoint else {
            drawCrosshair()
            return
        }

        let rect = normalizedRect(from: startPoint, to: currentPoint)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(rect: rect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()

        drawCrosshair(at: currentPoint)
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func convertToScreenCoordinates(_ rect: CGRect) -> CGRect {
        guard let window else { return rect }
        return window.convertToScreen(rect)
    }

    private func finishSelectionIfPossible() {
        guard let startPoint, let currentPoint else { return }
        let rect = normalizedRect(from: startPoint, to: currentPoint)
        if rect.width < 2 || rect.height < 2 {
            delegate?.captureAreaOverlayViewDidCancel(self)
            return
        }
        let screenRect = convertToScreenCoordinates(rect)
        delegate?.captureAreaOverlayView(self, didFinishWith: screenRect)
    }

    private func drawCrosshair(at point: CGPoint? = nil) {
        let center = point ?? currentPoint ?? .zero
        let length: CGFloat = 12
        NSColor.white.withAlphaComponent(0.9).setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: center.x - length, y: center.y))
        path.line(to: CGPoint(x: center.x + length, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - length))
        path.line(to: CGPoint(x: center.x, y: center.y + length))
        path.stroke()
    }
}


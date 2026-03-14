//
//  AllInOneCaptureOverlay.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import SwiftUI

// MARK: - Controller

final class AllInOneOverlayController: NSObject {
    static let shared = AllInOneOverlayController()

    private var overlayPanels: [NSPanel] = []
    private var toolbarPanel: NSPanel?
    private var activeOverlayView: OverlayContentView?
    private var escMonitor: Any?

    func show() {
        close()

        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let mouseScreen else { return }

        // Create overlay panel for each screen
        for screen in NSScreen.screens {
            let isPrimary = (screen == mouseScreen)
            let panel = createOverlayPanel(for: screen, isPrimary: isPrimary)
            overlayPanels.append(panel)
            panel.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        if let primaryPanel = overlayPanels.first(where: { $0 is KeyableOverlayPanel }) {
            primaryPanel.makeKeyAndOrderFront(nil)
        }
        if let activeOverlayView {
            updateToolbar(selectionRect: activeOverlayView.selection, screen: mouseScreen)
        }

        // ESC key monitor
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.close()
                return nil
            }
            return event
        }
    }

    func close() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
        escMonitor = nil
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        for panel in overlayPanels {
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
        activeOverlayView = nil
    }

    private func createOverlayPanel(for screen: NSScreen, isPrimary: Bool) -> NSPanel {
        let panel = KeyableOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        if isPrimary {
            let overlayView = OverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
            overlayView.screenFrame = screen.frame
            overlayView.onSelectionChanged = { [weak self] rect in
                self?.updateToolbar(selectionRect: rect, screen: screen)
            }
            overlayView.onClose = { [weak self] in
                self?.close()
            }
            overlayView.onCaptureArea = { [weak self] in
                self?.captureCurrentArea()
            }
            overlayView.onCaptureFullscreen = { [weak self] in
                self?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    CaptureAreaController.shared.captureFullScreen()
                }
            }
            overlayView.onCaptureWindow = { [weak self] in
                self?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    CaptureAreaController.shared.captureWindow()
                }
            }
            overlayView.onAnyMouseDown = { [weak self] in
                self?.toolbarPanel?.makeKeyAndOrderFront(nil)
            }
            panel.contentView = overlayView
            activeOverlayView = overlayView
            updateToolbar(selectionRect: overlayView.selection, screen: screen)
        } else {
            let selectView = ScreenSelectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            selectView.onSelect = { [weak self] in
                self?.switchToScreen(screen)
            }
            panel.contentView = selectView
        }

        return panel
    }

    private func switchToScreen(_ screen: NSScreen) {
        close()
        // Re-show with this screen as primary
        let panel = createOverlayPanel(for: screen, isPrimary: true)
        overlayPanels.append(panel)

        for otherScreen in NSScreen.screens where otherScreen != screen {
            let otherPanel = createOverlayPanel(for: otherScreen, isPrimary: false)
            overlayPanels.append(otherPanel)
        }

        for p in overlayPanels {
            p.orderFrontRegardless()
        }
        if let primaryPanel = overlayPanels.first(where: { $0 is KeyableOverlayPanel }) {
            primaryPanel.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func updateToolbar(selectionRect: CGRect, screen: NSScreen) {
        let effectiveSelection: CGRect
        if selectionRect.width > 2, selectionRect.height > 2 {
            effectiveSelection = selectionRect
        } else {
            effectiveSelection = defaultSelectionRect(for: screen)
        }

        // Convert overlay-local rect to screen coordinates
        let screenRect = CGRect(
            x: screen.frame.origin.x + effectiveSelection.origin.x,
            y: screen.frame.origin.y + (screen.frame.height - effectiveSelection.maxY),
            width: effectiveSelection.width,
            height: effectiveSelection.height
        )

        let toolbarWidth: CGFloat = 680
        let toolbarHeight: CGFloat = 56
        let gap: CGFloat = 12

        var toolbarX = screenRect.midX - toolbarWidth / 2
        var toolbarY = screenRect.minY - toolbarHeight - gap

        // If toolbar would go below screen, put it above
        if toolbarY < screen.visibleFrame.minY {
            toolbarY = screenRect.maxY + gap
        }
        // Clamp horizontal
        toolbarX = max(screen.visibleFrame.minX + 4, min(toolbarX, screen.visibleFrame.maxX - toolbarWidth - 4))

        if toolbarPanel == nil {
            let tp = ToolbarPanel(
                contentRect: NSRect(x: toolbarX, y: toolbarY, width: toolbarWidth, height: toolbarHeight),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            tp.isFloatingPanel = true
            tp.level = .screenSaver
            tp.isOpaque = false
            tp.backgroundColor = .clear
            tp.hasShadow = true
            tp.hidesOnDeactivate = false
            tp.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let toolbarView = ToolbarContentView { [weak self] action in
                switch action {
                case .area: self?.captureCurrentArea()
                case .fullscreen: self?.activeOverlayView?.onCaptureFullscreen?()
                case .window: self?.activeOverlayView?.onCaptureWindow?()
                case .scrolling: break
                case .timer: break
                case .ocr: self?.captureCurrentAreaOCR()
                case .recording: break
                }
            }
            tp.contentView = NSHostingView(rootView: toolbarView)
            toolbarPanel = tp
        }

        toolbarPanel?.setFrame(NSRect(x: toolbarX, y: toolbarY, width: toolbarWidth, height: toolbarHeight), display: true)

        // Update size label
        if let hostingView = toolbarPanel?.contentView as? NSHostingView<ToolbarContentView> {
            hostingView.rootView.selectionWidth = Int(effectiveSelection.width)
            hostingView.rootView.selectionHeight = Int(effectiveSelection.height)
        }

        toolbarPanel?.makeKeyAndOrderFront(nil)
    }

    private func defaultSelectionRect(for screen: NSScreen) -> CGRect {
        let maxWidth = screen.frame.width * 0.7
        let maxHeight = screen.frame.height * 0.35
        let width = min(720, maxWidth)
        let height = min(220, maxHeight)
        let x = (screen.frame.width - width) / 2
        let y = (screen.frame.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func captureCurrentArea() {
        guard let overlayView = activeOverlayView else { return }
        let sel = overlayView.selection
        guard sel.width > 2, sel.height > 2 else { return }

        let screenFrame = overlayView.screenFrame
        // Convert from flipped overlay coords to Cocoa screen coords
        let screenRect = CGRect(
            x: screenFrame.origin.x + sel.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - sel.maxY),
            width: sel.width,
            height: sel.height
        )

        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                await CaptureAreaController.shared.captureAndShow(rect: screenRect)
            }
        }
    }

    private func captureCurrentAreaOCR() {
        guard let overlayView = activeOverlayView else { return }
        let sel = overlayView.selection
        guard sel.width > 2, sel.height > 2 else { return }

        let screenFrame = overlayView.screenFrame
        let screenRect = CGRect(
            x: screenFrame.origin.x + sel.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - sel.maxY),
            width: sel.width,
            height: sel.height
        )

        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                await CaptureAreaController.shared.captureAndRecognizeText(rect: screenRect)
            }
        }
    }
}

// MARK: - Keyable Panel

private final class KeyableOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Overlay Content View (Pure AppKit)

private final class OverlayContentView: NSView {
    var screenFrame: CGRect = .zero
    var onSelectionChanged: ((CGRect) -> Void)?
    var onClose: (() -> Void)?
    var onCaptureArea: (() -> Void)?
    var onCaptureFullscreen: (() -> Void)?
    var onCaptureWindow: (() -> Void)?

    // Selection rect in flipped view coordinates (origin top-left)
    var selection: CGRect = .zero {
        didSet {
            needsDisplay = true
            onSelectionChanged?(selection)
        }
    }

    private enum DragMode {
        case none
        case drawing       // Drawing new rectangle
        case moving        // Moving existing rectangle
        case resizeTL, resizeTR, resizeBL, resizeBR
        case resizeT, resizeB, resizeL, resizeR
    }

    private var dragMode: DragMode = .none
    private var dragStart: CGPoint = .zero
    private var dragOriginalSelection: CGRect = .zero
    var onAnyMouseDown: (() -> Void)?

    private let handleSize: CGFloat = 8
    private let handleHitSize: CGFloat = 16
    private let defaultWidth: CGFloat = 756
    private let defaultHeight: CGFloat = 491

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // Set default selection centered
        let x = (frameRect.width - defaultWidth) / 2
        let y = (frameRect.height - defaultHeight) / 2
        selection = CGRect(x: x, y: y, width: defaultWidth, height: defaultHeight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds

        // Draw dimmed overlay with cutout
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addRect(bounds)
        if selection.width > 2, selection.height > 2 {
            ctx.addRect(selection)
        }
        ctx.drawPath(using: .eoFill)

        guard selection.width > 2, selection.height > 2 else { return }

        // White border around selection
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(selection.insetBy(dx: -0.75, dy: -0.75))

        // Draw corner L-handles and edge midpoint handles
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)

        let s = selection
        let hs = handleSize
        let cornerLen: CGFloat = 20

        // Corner L-handles
        drawCornerL(ctx: ctx, corner: CGPoint(x: s.minX, y: s.minY), dx: 1, dy: 1, len: cornerLen)
        drawCornerL(ctx: ctx, corner: CGPoint(x: s.maxX, y: s.minY), dx: -1, dy: 1, len: cornerLen)
        drawCornerL(ctx: ctx, corner: CGPoint(x: s.minX, y: s.maxY), dx: 1, dy: -1, len: cornerLen)
        drawCornerL(ctx: ctx, corner: CGPoint(x: s.maxX, y: s.maxY), dx: -1, dy: -1, len: cornerLen)

        // Edge midpoint handles (small rectangles)
        let midHandleW: CGFloat = 16
        let midHandleH: CGFloat = 5

        // Top edge
        ctx.fill(CGRect(x: s.midX - midHandleW/2, y: s.minY - midHandleH/2, width: midHandleW, height: midHandleH))
        // Bottom edge
        ctx.fill(CGRect(x: s.midX - midHandleW/2, y: s.maxY - midHandleH/2, width: midHandleW, height: midHandleH))
        // Left edge
        ctx.fill(CGRect(x: s.minX - midHandleH/2, y: s.midY - midHandleW/2, width: midHandleH, height: midHandleW))
        // Right edge
        ctx.fill(CGRect(x: s.maxX - midHandleH/2, y: s.midY - midHandleW/2, width: midHandleH, height: midHandleW))

        // Size label in top-left corner of selection
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

        // Horizontal arm
        ctx.move(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x + dx * len, y: corner.y))
        ctx.strokePath()

        // Vertical arm
        ctx.move(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * len))
        ctx.strokePath()
    }

    // MARK: Hit Testing

    private func hitTestHandle(at point: CGPoint) -> DragMode {
        let s = selection
        guard s.width > 2, s.height > 2 else { return .none }

        let hh = handleHitSize

        // Corners
        if CGRect(x: s.minX - hh/2, y: s.minY - hh/2, width: hh, height: hh).contains(point) { return .resizeTL }
        if CGRect(x: s.maxX - hh/2, y: s.minY - hh/2, width: hh, height: hh).contains(point) { return .resizeTR }
        if CGRect(x: s.minX - hh/2, y: s.maxY - hh/2, width: hh, height: hh).contains(point) { return .resizeBL }
        if CGRect(x: s.maxX - hh/2, y: s.maxY - hh/2, width: hh, height: hh).contains(point) { return .resizeBR }

        // Edges
        let edgeTol: CGFloat = 6
        if abs(point.y - s.minY) < edgeTol && point.x > s.minX + hh && point.x < s.maxX - hh { return .resizeT }
        if abs(point.y - s.maxY) < edgeTol && point.x > s.minX + hh && point.x < s.maxX - hh { return .resizeB }
        if abs(point.x - s.minX) < edgeTol && point.y > s.minY + hh && point.y < s.maxY - hh { return .resizeL }
        if abs(point.x - s.maxX) < edgeTol && point.y > s.minY + hh && point.y < s.maxY - hh { return .resizeR }

        // Inside selection = move
        if s.contains(point) { return .moving }

        return .none
    }

    // MARK: Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        onAnyMouseDown?()

        let mode = hitTestHandle(at: point)
        if mode != .none {
            dragMode = mode
            dragStart = point
            dragOriginalSelection = selection
        } else {
            // Start drawing new rectangle
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
            // Clamp to bounds
            newRect.origin.x = max(0, min(newRect.origin.x, bounds.width - newRect.width))
            newRect.origin.y = max(0, min(newRect.origin.y, bounds.height - newRect.height))
            selection = newRect

        case .resizeTL:
            let newMinX = min(clamped.x, dragOriginalSelection.maxX - 10)
            let newMinY = min(clamped.y, dragOriginalSelection.maxY - 10)
            selection = CGRect(
                x: newMinX, y: newMinY,
                width: dragOriginalSelection.maxX - newMinX,
                height: dragOriginalSelection.maxY - newMinY
            )

        case .resizeTR:
            let newMaxX = max(clamped.x, dragOriginalSelection.minX + 10)
            let newMinY = min(clamped.y, dragOriginalSelection.maxY - 10)
            selection = CGRect(
                x: dragOriginalSelection.minX, y: newMinY,
                width: newMaxX - dragOriginalSelection.minX,
                height: dragOriginalSelection.maxY - newMinY
            )

        case .resizeBL:
            let newMinX = min(clamped.x, dragOriginalSelection.maxX - 10)
            let newMaxY = max(clamped.y, dragOriginalSelection.minY + 10)
            selection = CGRect(
                x: newMinX, y: dragOriginalSelection.minY,
                width: dragOriginalSelection.maxX - newMinX,
                height: newMaxY - dragOriginalSelection.minY
            )

        case .resizeBR:
            let newMaxX = max(clamped.x, dragOriginalSelection.minX + 10)
            let newMaxY = max(clamped.y, dragOriginalSelection.minY + 10)
            selection = CGRect(
                x: dragOriginalSelection.minX, y: dragOriginalSelection.minY,
                width: newMaxX - dragOriginalSelection.minX,
                height: newMaxY - dragOriginalSelection.minY
            )

        case .resizeT:
            let newMinY = min(clamped.y, dragOriginalSelection.maxY - 10)
            selection = CGRect(
                x: dragOriginalSelection.minX, y: newMinY,
                width: dragOriginalSelection.width,
                height: dragOriginalSelection.maxY - newMinY
            )

        case .resizeB:
            let newMaxY = max(clamped.y, dragOriginalSelection.minY + 10)
            selection = CGRect(
                x: dragOriginalSelection.minX, y: dragOriginalSelection.minY,
                width: dragOriginalSelection.width,
                height: newMaxY - dragOriginalSelection.minY
            )

        case .resizeL:
            let newMinX = min(clamped.x, dragOriginalSelection.maxX - 10)
            selection = CGRect(
                x: newMinX, y: dragOriginalSelection.minY,
                width: dragOriginalSelection.maxX - newMinX,
                height: dragOriginalSelection.height
            )

        case .resizeR:
            let newMaxX = max(clamped.x, dragOriginalSelection.minX + 10)
            selection = CGRect(
                x: dragOriginalSelection.minX, y: dragOriginalSelection.minY,
                width: newMaxX - dragOriginalSelection.minX,
                height: dragOriginalSelection.height
            )

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode == .drawing && selection.width < 4 && selection.height < 4 {
            // Tiny drag = keep previous selection
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

// MARK: - Screen Select View (for non-primary screens)

private final class ScreenSelectView: NSView {
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

        // Dimmed overlay
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fill(bounds)

        // "Select This Screen" button
        let btnW: CGFloat = 220
        let btnH: CGFloat = 50
        buttonRect = CGRect(
            x: bounds.midX - btnW / 2,
            y: bounds.midY - btnH / 2,
            width: btnW,
            height: btnH
        )

        let bgColor = isHovering
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.white.withAlphaComponent(0.15)
        let path = CGPath(roundedRect: buttonRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillPath()

        // Border
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        // Text
        let text = "Select This Screen"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white
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
        if wasHovering != isHovering {
            NSCursor.pointingHand.set()
            needsDisplay = true
        }
        if !isHovering {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if buttonRect.contains(point) {
            onSelect?()
        }
    }
}

// MARK: - Toolbar (SwiftUI in separate panel)

private enum ToolbarAction {
    case area, fullscreen, window, scrolling, timer, ocr, recording
}

private struct ToolbarContentView: View {
    let onAction: (ToolbarAction) -> Void
    var selectionWidth: Int = 0
    var selectionHeight: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                SegmentButton(icon: "crop", label: "Area") { onAction(.area) }
                segmentDivider()
                SegmentButton(icon: "desktopcomputer", label: "Fullscreen") { onAction(.fullscreen) }
                segmentDivider()
                SegmentButton(icon: "macwindow", label: "Window") { onAction(.window) }
                segmentDivider()
                SegmentButton(icon: "arrow.down.to.line", label: "Scrolling") { onAction(.scrolling) }
                segmentDivider()
                SegmentButton(icon: "timer", label: "Timer") { onAction(.timer) }
                segmentDivider()
                SegmentButton(icon: "text.viewfinder", label: "OCR") { onAction(.ocr) }
                segmentDivider()
                SegmentButton(icon: "video", label: "Recording") { onAction(.recording) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )

            if selectionWidth > 0 && selectionHeight > 0 {
                HStack(spacing: 8) {
                    Text("\(selectionWidth) × \(selectionHeight)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))

                    Button(action: {}) {
                        Image(systemName: "arrow.2.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.9))

                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 1, height: 16)

                    Button(action: {}) {
                        Image(systemName: "crop")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.leading, -2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.92))
                )
            }
        }
        .frame(height: 56)
        .environment(\.colorScheme, .dark)
    }

    private struct SegmentButton: View {
        let icon: String
        let label: String
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(isHovering ? 1.0 : 0.8))
                .frame(width: 62, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? .white.opacity(0.12) : .white.opacity(0.001))
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
    }

    private func segmentDivider() -> some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }
}

#Preview {
    ToolbarContentView(onAction: { _ in }, selectionWidth: 720, selectionHeight: 220)
        .frame(width: 680, height: 56)
        .background(.black)
}

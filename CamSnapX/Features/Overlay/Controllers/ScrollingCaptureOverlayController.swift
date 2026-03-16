//
//  ScrollingCaptureOverlayController.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import SwiftUI

/// A standalone overlay controller dedicated to scrolling capture.
/// Completely separate from AllInOneOverlayController.
final class ScrollingCaptureOverlayController: NSObject, ScrollingCaptureDelegate {
    static let shared = ScrollingCaptureOverlayController()

    private var overlayPanels: [NSPanel] = []
    private var activeOverlayView: OverlayContentView?
    private var escMonitor: Any?
    private var scrollingControlPanel: NSPanel?
    private var selectionBorderPanel: NSPanel?
    private let scrollingCaptureManager = ScrollingCaptureManager()
    private let scrollingControlModel = ScrollingCaptureControlModel()
    private var currentSelectionRect: CGRect = .zero
    private var currentScreen: NSScreen?

    // Scroll event monitoring
    private var scrollingGlobalMonitor: Any?
    private var scrollingLocalMonitor: Any?
    private var scrollingDeltaAccumulator: CGFloat = 0
    private var scrollingCaptureThreshold: CGFloat = 140
    private var scrollingDirection: CGFloat = 0
    private var lastCaptureTime: CFTimeInterval = 0
    private let minCaptureInterval: CFTimeInterval = 0.25
    private let scrollRenderDelay: CFTimeInterval = 0.26
    private var scrollCaptureWorkItem: DispatchWorkItem?

    /// Tracks whether the user has drawn a selection yet
    private var hasSelection = false
    /// The "Start Capture" button panel shown after user draws a selection
    private var startButtonPanel: NSPanel?

    private override init() {
        super.init()
        scrollingCaptureManager.delegate = self
    }

    // MARK: - Public API

    func show() {
        close()

        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let mouseScreen else { return }

        hasSelection = false

        // Create the same overlay on every screen (no "select this screen" prompt)
        for screen in NSScreen.screens {
            let isPrimary = (screen == mouseScreen)
            let panel = createOverlayPanel(for: screen, isPrimary: isPrimary)
            overlayPanels.append(panel)
            panel.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        // Make the panel on the mouse screen the key window
        if let mousePanel = overlayPanels.first(where: { $0.frame.intersects(mouseScreen.frame) }) {
            mousePanel.makeKeyAndOrderFront(nil)
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
        if scrollingCaptureManager.isScrollingCaptureActive {
            scrollingCaptureManager.endScrollingCapture(shouldCapture: false)
        }
        hideScrollingCaptureControls()
        hideSelectionBorder()
        hideStartButton()
        stopScrollMonitor()
        for panel in overlayPanels {
            panel.ignoresMouseEvents = false
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
        activeOverlayView = nil
    }

    // MARK: - Panel Creation

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

        let overlayView = OverlayContentView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            initialSelectionEnabled: false
        )
        overlayView.screenFrame = screen.frame
        overlayView.showsSelectionOverlay = false
        overlayView.showsDimOverlay = false
        overlayView.showsScrollHint = true

        overlayView.onSelectionChanged = { [weak self] rect in
            self?.handleSelectionChanged(rect: rect, screen: screen)
        }
        overlayView.onClose = { [weak self] in
            self?.close()
        }
        overlayView.onCaptureArea = { [weak self] in
            // Enter key starts capture if we have a selection
            if self?.hasSelection == true {
                self?.startScrollingCapture()
            }
        }

        panel.contentView = overlayView
        if isPrimary {
            activeOverlayView = overlayView
            currentScreen = screen
        }

        return panel
    }

    // MARK: - Selection Handling

    private func handleSelectionChanged(rect: CGRect, screen: NSScreen) {
        currentSelectionRect = rect
        currentScreen = screen

        if rect.width > 10 && rect.height > 10 {
            if !hasSelection {
                hasSelection = true
            }
            showStartButton(selectionRect: rect, screen: screen)
        }
    }

    // MARK: - Start Button

    private func showStartButton(selectionRect: CGRect, screen: NSScreen) {
        let buttonWidth: CGFloat = 260
        let buttonHeight: CGFloat = 56
        let gap: CGFloat = 12

        let screenRect = self.screenRect(from: selectionRect, screenFrame: screen.frame)

        var btnX = screenRect.midX - buttonWidth / 2
        var btnY: CGFloat

        let spaceBelow = screenRect.minY - screen.visibleFrame.minY
        let spaceAbove = screen.visibleFrame.maxY - screenRect.maxY

        if spaceAbove >= buttonHeight + gap && spaceAbove >= spaceBelow {
            btnY = screenRect.maxY + gap
        } else if spaceBelow >= buttonHeight + gap {
            btnY = screenRect.minY - buttonHeight - gap
        } else {
            btnY = screenRect.midY - buttonHeight / 2
        }

        btnX = max(screen.visibleFrame.minX + 4, min(btnX, screen.visibleFrame.maxX - buttonWidth - 4))

        if startButtonPanel == nil {
            let tp = ToolbarPanel(
                contentRect: NSRect(x: btnX, y: btnY, width: buttonWidth, height: buttonHeight),
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

            let startView = ScrollingCaptureStartButtonView { [weak self] in
                self?.startScrollingCapture()
            }
            tp.contentView = NSHostingView(rootView: startView)
            startButtonPanel = tp
        }

        startButtonPanel?.setFrame(
            NSRect(x: btnX, y: btnY, width: buttonWidth, height: buttonHeight),
            display: true, animate: false
        )
        startButtonPanel?.orderFrontRegardless()
    }

    private func hideStartButton() {
        startButtonPanel?.orderOut(nil)
        startButtonPanel = nil
    }

    // MARK: - Start Scrolling Capture

    private func startScrollingCapture() {
        hideStartButton()
        scrollingCaptureManager.startScrollingCapture()
    }

    // MARK: - Coordinate Helpers

    private func screenRect(from selection: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.origin.x + selection.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - selection.maxY),
            width: selection.width,
            height: selection.height
        )
    }

    // MARK: - ScrollingCaptureDelegate

    func showScrollingCaptureShelf() {
        // Not used in standalone mode — we go straight to capture
    }

    func hideScrollingCaptureShelf() {
        // Not used in standalone mode
    }

    func showScrollingCaptureControls() {
        guard let screen = currentScreen ?? NSScreen.main else { return }
        guard scrollingControlPanel == nil else {
            scrollingControlPanel?.orderFrontRegardless()
            return
        }

        scrollingControlModel.previewImage = nil
        scrollingControlModel.capturedHeight = 0
        let controlSize = CGSize(width: 300, height: 292)
        let panel = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: controlSize.width, height: controlSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none

        let controlView = ScrollingCaptureControlView(
            onCancel: { [weak self] in
                self?.scrollingCaptureManager.endScrollingCapture(shouldCapture: false)
            },
            onDone: { [weak self] in
                self?.scrollingCaptureManager.endScrollingCapture(shouldCapture: true)
            },
            showProgress: true,
            model: scrollingControlModel
        )
        panel.contentView = NSHostingView(rootView: controlView)
        scrollingControlPanel = panel

        positionControlPanel(screen: screen, size: controlSize)
        panel.orderFrontRegardless()
    }

    func hideScrollingCaptureControls() {
        scrollingControlPanel?.orderOut(nil)
        scrollingControlPanel = nil
    }

    // MARK: - Selection Border (visible during scrolling capture)

    private func showSelectionBorder() {
        guard let screen = currentScreen ?? NSScreen.main else { return }
        hideSelectionBorder()

        let selRect = screenRect(from: currentSelectionRect, screenFrame: screen.frame)

        let panel = NonKeyPanel(
            contentRect: selRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none

        let borderView = SelectionBorderView(frame: NSRect(origin: .zero, size: selRect.size))
        panel.contentView = borderView
        selectionBorderPanel = panel
        panel.orderFrontRegardless()
    }

    private func hideSelectionBorder() {
        selectionBorderPanel?.orderOut(nil)
        selectionBorderPanel = nil
    }

    func closeOverlay() {
        close()
    }

    func showPreviewForImage(_ image: NSImage) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            CaptureAreaController.shared.showPreviewForImage(image)
        }
    }

    func setSelectionOverlayVisible(_ visible: Bool) {
        activeOverlayView?.showsSelectionOverlay = visible
        if visible {
            activeOverlayView?.needsDisplay = true
        }
    }

    func setPanelsIgnoreMouseEvents(_ ignore: Bool) {
        if ignore {
            for panel in overlayPanels {
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0
            }
            showSelectionBorder()
            scrollingDeltaAccumulator = 0
            scrollingDirection = 0
            lastCaptureTime = 0
            startScrollMonitor()
        } else {
            stopScrollMonitor()
            hideSelectionBorder()
            for panel in overlayPanels {
                panel.ignoresMouseEvents = false
                panel.alphaValue = 1
            }
        }
    }

    func captureScrollFrame() {
        captureScrollingFrame()
    }

    func didUpdateStitchedPreview(_ image: CGImage, totalHeight: Int) {
        let maxPreviewHeight = 300
        let scale = min(1.0, CGFloat(maxPreviewHeight) / CGFloat(image.height))
        let tw = max(1, Int(CGFloat(image.width) * scale))
        let th = max(1, Int(CGFloat(image.height) * scale))

        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let thumb = ctx.makeImage() else { return }
        let nsImage = NSImage(cgImage: thumb, size: NSSize(width: tw, height: th))

        DispatchQueue.main.async { [weak self] in
            self?.scrollingControlModel.previewImage = nsImage
            self?.scrollingControlModel.capturedHeight = totalHeight
        }
    }

    // MARK: - Control Panel Positioning

    private func positionControlPanel(screen: NSScreen, size: CGSize) {
        guard let panel = scrollingControlPanel else { return }

        let selectionRect = self.screenRect(from: currentSelectionRect, screenFrame: screen.frame)
        let visible = screen.visibleFrame
        let gap: CGFloat = 12
        let margin: CGFloat = 12

        let candidates: [CGPoint] = [
            CGPoint(x: selectionRect.maxX + gap, y: selectionRect.midY - size.height / 2),
            CGPoint(x: selectionRect.minX - gap - size.width, y: selectionRect.midY - size.height / 2),
            CGPoint(x: selectionRect.midX - size.width / 2, y: selectionRect.maxY + gap),
            CGPoint(x: selectionRect.midX - size.width / 2, y: selectionRect.minY - gap - size.height),
            CGPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        ]

        func clamped(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: max(visible.minX + margin, min(p.x, visible.maxX - size.width - margin)),
                y: max(visible.minY + margin, min(p.y, visible.maxY - size.height - margin))
            )
        }

        let chosen = candidates
            .map(clamped)
            .first(where: { !CGRect(origin: $0, size: size).intersects(selectionRect) })
            ?? clamped(candidates.last ?? .zero)

        panel.setFrame(NSRect(origin: chosen, size: size), display: true, animate: false)
    }
}

// MARK: - Scroll Event Handling

private extension ScrollingCaptureOverlayController {
    func updateScrollThresholdForSelection() {
        let height = max(0, currentSelectionRect.height)
        let dynamic = height * 0.24
        let clamped = max(120, min(260, dynamic))
        scrollingCaptureThreshold = clamped
    }

    func startScrollMonitor() {
        stopScrollMonitor()
        updateScrollThresholdForSelection()
        scrollingGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
        }
        scrollingLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
            return event
        }
    }

    func stopScrollMonitor() {
        if let scrollingGlobalMonitor {
            NSEvent.removeMonitor(scrollingGlobalMonitor)
        }
        scrollingGlobalMonitor = nil
        if let scrollingLocalMonitor {
            NSEvent.removeMonitor(scrollingLocalMonitor)
        }
        scrollingLocalMonitor = nil
        scrollCaptureWorkItem?.cancel()
        scrollCaptureWorkItem = nil
    }

    func handleScrollEvent(_ event: NSEvent) {
        guard scrollingCaptureManager.isScrollingCaptureActive else { return }
        let rawDelta = event.scrollingDeltaY
        if rawDelta == 0 { return }
        let direction = rawDelta > 0 ? 1.0 : -1.0
        if scrollingDirection == 0 {
            scrollingDirection = direction
        } else if scrollingDirection != direction {
            scrollingDirection = direction
            scrollingDeltaAccumulator = 0
        }

        let delta = abs(rawDelta)
        let threshold = event.hasPreciseScrollingDeltas
            ? max(60, scrollingCaptureThreshold * 0.5)
            : scrollingCaptureThreshold
        scrollingDeltaAccumulator += delta
        if scrollingDeltaAccumulator >= threshold {
            scrollingDeltaAccumulator = 0

            let now = CACurrentMediaTime()
            if now - lastCaptureTime >= minCaptureInterval {
                lastCaptureTime = now

                // Cancel any pending delayed capture since we're capturing now
                scrollCaptureWorkItem?.cancel()
                scrollCaptureWorkItem = nil

                // Schedule capture after a brief render delay to let the
                // scroll settle on screen before taking a screenshot
                let workItem = DispatchWorkItem { [weak self] in
                    self?.scrollingCaptureManager.userDidScroll()
                }
                scrollCaptureWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + scrollRenderDelay, execute: workItem)
            }
        }
    }

    func captureScrollingFrame() {
        guard scrollingCaptureManager.isScrollingCaptureActive else { return }
        guard let screen = currentScreen else { return }
        let selection = currentSelectionRect
        guard selection.width > 2, selection.height > 2 else { return }

        let screenRect = self.screenRect(from: selection, screenFrame: screen.frame)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cgImage = await CaptureAreaController.shared.capturePreviewCGImage(rect: screenRect) {
                self.scrollingCaptureManager.appendScrollingFrame(cgImage)
            }
        }
    }
}

// MARK: - Start Button View

struct ScrollingCaptureStartButtonView: View {
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.and.down.square")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)

            Text("Start Capture")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onStart) {
                Text("Start")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .environment(\.colorScheme, .dark)
    }
}

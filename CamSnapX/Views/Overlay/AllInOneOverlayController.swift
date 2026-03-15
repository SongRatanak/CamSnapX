//
//  AllInOneOverlayController.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import SwiftUI

final class AllInOneOverlayController: NSObject, ScrollingCaptureDelegate {
    static let shared = AllInOneOverlayController()

    private var overlayPanels: [NSPanel] = []
    private var toolbarPanel: NSPanel?
    private var activeOverlayView: OverlayContentView?
    private var escMonitor: Any?
    private var scrollingPanel: NSPanel?
    private var scrollingControlPanel: NSPanel?
    private let scrollingViewModel = ScrollingCaptureViewModel()
    private var currentSelectionRect: CGRect = .zero
    private var currentScreen: NSScreen?
    private var savedSelection: CGRect?  // persists across overlay sessions
    private let scrollingCaptureManager = ScrollingCaptureManager()
    private let scrollingControlModel = ScrollingCaptureControlModel()
    private var scrollingGlobalMonitor: Any?
    private var scrollingLocalMonitor: Any?
    private var scrollingDeltaAccumulator: CGFloat = 0
    private var scrollingCaptureThreshold: CGFloat = 140
    private var scrollingDirection: CGFloat = 0
    private var lastCaptureTime: CFTimeInterval = 0
    private let minCaptureInterval: CFTimeInterval = 0.25  // capture at most every 250ms
    private let scrollRenderDelay: CFTimeInterval = 0.26
    private var scrollCaptureWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        scrollingCaptureManager.delegate = self
    }

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
        // Save current selection for next time
        if let overlayView = activeOverlayView, overlayView.selection.width > 2, overlayView.selection.height > 2 {
            savedSelection = overlayView.selection
        }
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        hideScrollingCaptureShelf()
        hideScrollingCaptureControls()
        stopScrollMonitor()
        activeOverlayView?.showsSelectionOverlay = true
        for panel in overlayPanels {
            panel.ignoresMouseEvents = false
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
            // Restore saved selection if available
            if let saved = savedSelection {
                overlayView.selection = saved
            }
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
                if let hostingView = self?.toolbarPanel?.contentView as? NSHostingView<ToolbarContentView> {
                    hostingView.rootView.isUserEditing = false
                }
            }
            panel.contentView = overlayView
            activeOverlayView = overlayView
            currentScreen = screen
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

        if let activeOverlayView {
            updateToolbar(selectionRect: activeOverlayView.selection, screen: screen)
        }

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

        let screenRect = CGRect(
            x: screen.frame.origin.x + effectiveSelection.origin.x,
            y: screen.frame.origin.y + (screen.frame.height - effectiveSelection.maxY),
            width: effectiveSelection.width,
            height: effectiveSelection.height
        )

        let toolbarWidth: CGFloat = 780
        let toolbarHeight: CGFloat = 56
        let gap: CGFloat = 12

        var toolbarX = screenRect.midX - toolbarWidth / 2
        var toolbarY: CGFloat

        let spaceBelow = screenRect.minY - screen.visibleFrame.minY
        let spaceAbove = screen.visibleFrame.maxY - screenRect.maxY

        if spaceAbove >= toolbarHeight + gap && spaceAbove >= spaceBelow {
            toolbarY = screenRect.maxY + gap
        } else if spaceBelow >= toolbarHeight + gap {
            toolbarY = screenRect.minY - toolbarHeight - gap
        } else {
            toolbarY = screenRect.midY - toolbarHeight / 2
        }

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

            var toolbarView = ToolbarContentView { [weak self] action in
                switch action {
                case .area: self?.captureCurrentArea()
                case .fullscreen: self?.activeOverlayView?.onCaptureFullscreen?()
                case .window: self?.activeOverlayView?.onCaptureWindow?()
                case .scrolling: self?.scrollingCaptureManager.startScrollingCapture()
                case .timer: break
                case .ocr: self?.captureCurrentAreaOCR()
                case .recording: break
                }
                if action != .scrolling {
                    self?.hideScrollingCaptureShelf()
                }
            }
            toolbarView.onSizeChanged = { [weak self] newWidth, newHeight in
                self?.resizeSelection(to: CGSize(width: CGFloat(newWidth), height: CGFloat(newHeight)))
            }
            toolbarView.onToggleFullscreen = { [weak self] in
                self?.toggleFullscreenSelection()
            }
            tp.contentView = NSHostingView(rootView: toolbarView)
            toolbarPanel = tp
        }

        toolbarPanel?.setFrame(NSRect(x: toolbarX, y: toolbarY, width: toolbarWidth, height: toolbarHeight), display: true, animate: false)

        let newWidth = Int(effectiveSelection.width)
        let newHeight = Int(effectiveSelection.height)
        currentSelectionRect = effectiveSelection
        currentScreen = screen
        DispatchQueue.main.async { [weak self] in
            if let hostingView = self?.toolbarPanel?.contentView as? NSHostingView<ToolbarContentView> {
                hostingView.rootView.selectionWidth = newWidth
                hostingView.rootView.selectionHeight = newHeight
            }
        }

        toolbarPanel?.orderFrontRegardless()
        updateScrollingShelfIfNeeded(selectionRect: effectiveSelection, screen: screen)
    }

    private func defaultSelectionRect(for screen: NSScreen) -> CGRect {
        let width = screen.frame.width * 0.55
        let height = screen.frame.height * 0.55
        let x = (screen.frame.width - width) / 2
        let y = (screen.frame.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func resizeSelection(to newSize: CGSize) {
        guard let overlayView = activeOverlayView else { return }
        let oldSel = overlayView.selection
        let clampedWidth = min(newSize.width, overlayView.bounds.width)
        let clampedHeight = min(newSize.height, overlayView.bounds.height)
        let centerX = oldSel.midX
        let centerY = oldSel.midY
        var newX = centerX - clampedWidth / 2
        var newY = centerY - clampedHeight / 2
        newX = max(0, min(newX, overlayView.bounds.width - clampedWidth))
        newY = max(0, min(newY, overlayView.bounds.height - clampedHeight))
        overlayView.selection = CGRect(x: newX, y: newY, width: clampedWidth, height: clampedHeight)
    }

    private func toggleFullscreenSelection() {
        guard let overlayView = activeOverlayView else { return }
        let bounds = overlayView.bounds
        if overlayView.selection == bounds {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let screen {
                overlayView.selection = defaultSelectionRect(for: screen)
            }
        } else {
            overlayView.selection = bounds
        }
    }

    private func captureCurrentArea() {
        guard let overlayView = activeOverlayView else { return }
        let sel = overlayView.selection
        guard sel.width > 2, sel.height > 2 else { return }

        let screenRect = screenRect(from: sel, screenFrame: overlayView.screenFrame)

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

        let screenRect = screenRect(from: sel, screenFrame: overlayView.screenFrame)

        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                await CaptureAreaController.shared.captureAndRecognizeText(rect: screenRect)
            }
        }
    }
    internal func showScrollingCaptureShelf() {
        guard let screen = currentScreen ?? NSScreen.main else { return }
        guard scrollingPanel == nil else {
            scrollingPanel?.orderFrontRegardless()
            return
        }

        let shelfSize = CGSize(width: 340, height: 120)
        let panel = ToolbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: shelfSize.width, height: shelfSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let shelfView = ScrollingCaptureShelfView(model: scrollingViewModel) { [weak self] in
            self?.scrollingCaptureManager.startScrollingCapture()
        }
        panel.contentView = NSHostingView(rootView: shelfView)
        scrollingPanel = panel

        updateScrollingShelfIfNeeded(selectionRect: currentSelectionRect, screen: screen)
        panel.orderFrontRegardless()
    }

    internal func hideScrollingCaptureShelf() {
        scrollingPanel?.orderOut(nil)
        scrollingPanel = nil
    }

    private func updateScrollingShelfIfNeeded(selectionRect: CGRect, screen: NSScreen) {
        guard let scrollingPanel else { return }

        let screenRect = screenRect(from: selectionRect, screenFrame: screen.frame)
        let shelfSize = CGSize(width: scrollingPanel.frame.width, height: scrollingPanel.frame.height)
        let gap: CGFloat = 12

        var shelfX = screenRect.maxX + gap
        if shelfX + shelfSize.width > screen.visibleFrame.maxX {
            shelfX = screenRect.minX - gap - shelfSize.width
        }
        shelfX = max(screen.visibleFrame.minX + 4, min(shelfX, screen.visibleFrame.maxX - shelfSize.width - 4))

        var shelfY = screenRect.midY - shelfSize.height / 2
        shelfY = max(screen.visibleFrame.minY + 4, min(shelfY, screen.visibleFrame.maxY - shelfSize.height - 4))

        scrollingPanel.setFrame(NSRect(x: shelfX, y: shelfY, width: shelfSize.width, height: shelfSize.height), display: true, animate: false)
        scrollingViewModel.selectionSize = selectionRect.size
    }

    private func screenRect(from selection: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.origin.x + selection.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - selection.maxY),
            width: selection.width,
            height: selection.height
        )
    }

    private func positionScrollingControlPanel(screen: NSScreen, size: CGSize) {
        guard let panel = scrollingControlPanel else { return }

        let selectionRect = screenRect(from: currentSelectionRect, screenFrame: screen.frame)
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

    internal func showScrollingCaptureControls() {
        guard let screen = currentScreen ?? NSScreen.main else { return }
        guard scrollingControlPanel == nil else {
            scrollingControlPanel?.orderFrontRegardless()
            return
        }

        // Reset control model
        scrollingControlModel.previewImage = nil
        scrollingControlModel.capturedHeight = 0
        let controlSize = CGSize(width: 248, height: 252)
        let panel = ToolbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: controlSize.width, height: controlSize.height),
            styleMask: [.borderless],
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

        positionScrollingControlPanel(screen: screen, size: controlSize)
        panel.orderFrontRegardless()
    }

    internal func hideScrollingCaptureControls() {
        scrollingControlPanel?.orderOut(nil)
        scrollingControlPanel = nil
    }


}

// MARK: - Scroll Event Handling for Scrolling Capture

private extension AllInOneOverlayController {
    func updateScrollThresholdForSelection() {
        let height = max(0, currentSelectionRect.height)
        let dynamic = height * 0.24
        let clamped = max(120, min(260, dynamic))
        scrollingCaptureThreshold = clamped
    }

    func startScrollMonitor() {
        stopScrollMonitor()
        updateScrollThresholdForSelection()
        // Global monitor: catches scroll events going to other apps
        scrollingGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
        }
        // Local monitor: catches scroll events going to our own panels (toolbar, controls)
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
        scrollingDeltaAccumulator += delta
        if scrollingDeltaAccumulator >= scrollingCaptureThreshold {
            scrollingDeltaAccumulator = 0

            // Throttle: capture at most once per minCaptureInterval
            let now = CACurrentMediaTime()
            if now - lastCaptureTime >= minCaptureInterval {
                lastCaptureTime = now

                // Cancel any pending capture and schedule a new one after render delay
                scrollCaptureWorkItem?.cancel()
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
        guard let overlayView = activeOverlayView else { return }

        let selection = overlayView.selection
        guard selection.width > 2, selection.height > 2 else { return }

        let screenRect = screenRect(from: selection, screenFrame: overlayView.screenFrame)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cgImage = await CaptureAreaController.shared.capturePreviewCGImage(rect: screenRect) {
                self.scrollingCaptureManager.appendScrollingFrame(cgImage)
            }
        }
    }
}

// MARK: - ScrollingCaptureDelegate

extension AllInOneOverlayController {
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
            // Make overlay panels fully transparent & pass-through during scroll capture
            for panel in overlayPanels {
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0
            }
            // Hide toolbar and shelf — only show the Done/Cancel control
            toolbarPanel?.orderOut(nil)
            scrollingPanel?.orderOut(nil)

            scrollingDeltaAccumulator = 0
            scrollingDirection = 0
            lastCaptureTime = 0
            startScrollMonitor()
        } else {
            stopScrollMonitor()
            for panel in overlayPanels {
                panel.ignoresMouseEvents = false
                panel.alphaValue = 1
            }
            toolbarPanel?.orderFrontRegardless()
        }
    }

    func captureScrollFrame() {
        captureScrollingFrame()
    }

    func didUpdateStitchedPreview(_ image: CGImage, totalHeight: Int) {
        // Live preview only while active scrolling capture (not in pre-capture shelf).
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
}

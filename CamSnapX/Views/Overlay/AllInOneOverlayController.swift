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
    private var scrollingPreviewTimer: Timer?
    private var currentSelectionRect: CGRect = .zero
    private var currentScreen: NSScreen?
    private let scrollingCaptureManager = ScrollingCaptureManager()
    private var scrollingMonitor: Any?
    private var scrollingDeltaAccumulator: CGFloat = 0
    private let scrollingCaptureThreshold: CGFloat = 220
    private var scrollingDirection: CGFloat = 0

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
                case .scrolling: self?.showScrollingCaptureShelf()
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
        startScrollingPreviewTimer()
        panel.orderFrontRegardless()
    }

    internal func hideScrollingCaptureShelf() {
        scrollingPreviewTimer?.invalidate()
        scrollingPreviewTimer = nil
        scrollingViewModel.previewImage = nil
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
        updateScrollingPreview()
    }

    private func startScrollingPreviewTimer() {
        scrollingPreviewTimer?.invalidate()
        scrollingPreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateScrollingPreview()
        }
    }

    private func updateScrollingPreview() {
        guard scrollingPanel != nil else { return }
        guard let overlayView = activeOverlayView else { return }

        let selection = overlayView.selection
        guard selection.width > 2, selection.height > 2 else {
            scrollingViewModel.previewImage = nil
            return
        }

        let screenRect = screenRect(from: selection, screenFrame: overlayView.screenFrame)
        Task { @MainActor in
            self.scrollingViewModel.previewImage = await CaptureAreaController.shared.capturePreviewImage(rect: screenRect)
        }
    }

    private func screenRect(from selection: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.origin.x + selection.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - selection.maxY),
            width: selection.width,
            height: selection.height
        )
    }

    internal func showScrollingCaptureControls() {
        guard let screen = currentScreen ?? NSScreen.main else { return }
        guard scrollingControlPanel == nil else {
            scrollingControlPanel?.orderFrontRegardless()
            return
        }

        let controlSize = CGSize(width: 180, height: 70)
        let panel = ToolbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: controlSize.width, height: controlSize.height),
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

        let controlView = ScrollingCaptureControlView(
            onCancel: { [weak self] in
                self?.scrollingCaptureManager.endScrollingCapture(shouldCapture: false)
            },
            onDone: { [weak self] in
                self?.scrollingCaptureManager.endScrollingCapture(shouldCapture: true)
            },
            showProgress: true
        )
        panel.contentView = NSHostingView(rootView: controlView)
        scrollingControlPanel = panel

        let selection = currentSelectionRect
        let screenRect = screenRect(from: selection, screenFrame: screen.frame)
        let gap: CGFloat = 10
        var panelX = screenRect.midX - controlSize.width / 2
        var panelY = screenRect.maxY + gap
        if panelY + controlSize.height > screen.visibleFrame.maxY {
            panelY = screenRect.minY - controlSize.height - gap
        }
        panelX = max(screen.visibleFrame.minX + 4, min(panelX, screen.visibleFrame.maxX - controlSize.width - 4))
        panelY = max(screen.visibleFrame.minY + 4, min(panelY, screen.visibleFrame.maxY - controlSize.height - 4))

        panel.setFrame(NSRect(x: panelX, y: panelY, width: controlSize.width, height: controlSize.height), display: true, animate: false)
        panel.orderFrontRegardless()
    }

    internal func hideScrollingCaptureControls() {
        scrollingControlPanel?.orderOut(nil)
        scrollingControlPanel = nil
    }


}

// MARK: - Scroll Event Handling for Scrolling Capture

private extension AllInOneOverlayController {
    func startScrollMonitor() {
        stopScrollMonitor()
        scrollingMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
        }
    }

    func stopScrollMonitor() {
        if let scrollingMonitor {
            NSEvent.removeMonitor(scrollingMonitor)
        }
        scrollingMonitor = nil
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
            captureScrollingFrame()
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
            if let image = await CaptureAreaController.shared.capturePreviewImage(rect: screenRect),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
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
    }

    func setPanelsIgnoreMouseEvents(_ ignore: Bool) {
        for panel in overlayPanels {
            panel.ignoresMouseEvents = ignore
        }
    }

    func captureScrollFrame() {
        captureScrollingFrame()
    }
}

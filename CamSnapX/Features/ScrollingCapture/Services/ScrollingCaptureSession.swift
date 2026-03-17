//
//  ScrollingCaptureSession.swift
//  CamSnapX
//
//  Centralizes scrolling capture logic so it is shared across overlays.
//

import AppKit
import SwiftUI

protocol ScrollingCaptureSessionHost: AnyObject {
    var sessionSelectionRect: CGRect { get }
    var sessionScreen: NSScreen? { get }
    var sessionOverlayPanels: [NSPanel] { get }

    func sessionRequestClose()
    func sessionDidProduceImage(_ image: NSImage)

    func sessionShowScrollingControls()
    func sessionHideScrollingControls()

    func sessionHideExtraPanels()
    func sessionRestoreExtraPanels()

    func sessionShowScrollingShelf()
    func sessionHideScrollingShelf()

    func sessionSetSelectionOverlayVisible(_ visible: Bool)
    func sessionDidUpdateStitchedPreview(_ image: CGImage, totalHeight: Int)
    func sessionDidDetectScrollTooFast()
}

extension ScrollingCaptureSessionHost {
    func sessionHideExtraPanels() {}
    func sessionRestoreExtraPanels() {}
    func sessionShowScrollingShelf() {}
    func sessionHideScrollingShelf() {}
}

final class ScrollingCaptureSession: ScrollingCaptureDelegate {
    // MARK: - Constants
    private static let minCaptureInterval: CFTimeInterval = 0.15
    private static let scrollRenderDelay: CFTimeInterval = 0.12
    private static let thresholdMultiplier: CGFloat = 0.18
    private static let thresholdMin: CGFloat = 80
    private static let thresholdMax: CGFloat = 200
    private static let preciseScrollMultiplier: CGFloat = 0.2
    private static let preciseScrollMin: CGFloat = 20

    // MARK: - State
    weak var host: ScrollingCaptureSessionHost?
    let manager = ScrollingCaptureManager()

    private var scrollingGlobalMonitor: Any?
    private var scrollingLocalMonitor: Any?
    private var scrollingDeltaAccumulator: CGFloat = 0
    private var scrollingCaptureThreshold: CGFloat = 140
    private var scrollingDirection: CGFloat = 0
    private var lastCaptureTime: CFTimeInterval = 0
    private var scrollCaptureWorkItem: DispatchWorkItem?

    private var selectionBorderPanel: NSPanel?

    init() {
        manager.delegate = self
    }

    // MARK: - Public API

    func startCapture() {
        manager.startScrollingCapture()
    }

    func cancelCapture() {
        manager.endScrollingCapture(shouldCapture: false)
    }

    func finishCapture() {
        manager.endScrollingCapture(shouldCapture: true)
    }

    func tearDown() {
        if manager.isScrollingCaptureActive {
            manager.endScrollingCapture(shouldCapture: false)
        }
        hideScrollingCaptureControls()
        hideSelectionBorder()
        stopScrollMonitor()
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
        host?.sessionShowScrollingShelf()
    }

    func hideScrollingCaptureShelf() {
        host?.sessionHideScrollingShelf()
    }

    func showScrollingCaptureControls() {
        host?.sessionShowScrollingControls()
    }

    func hideScrollingCaptureControls() {
        host?.sessionHideScrollingControls()
    }

    func closeOverlay() {
        host?.sessionRequestClose()
    }

    func showPreviewForImage(_ image: NSImage) {
        host?.sessionDidProduceImage(image)
    }

    func setSelectionOverlayVisible(_ visible: Bool) {
        host?.sessionSetSelectionOverlayVisible(visible)
    }

    func setPanelsIgnoreMouseEvents(_ ignore: Bool) {
        guard let host else { return }
        if ignore {
            for panel in host.sessionOverlayPanels {
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0
                panel.sharingType = .none
            }
            host.sessionHideExtraPanels()
            showSelectionBorder()
            scrollingDeltaAccumulator = 0
            scrollingDirection = 0
            lastCaptureTime = 0
            startScrollMonitor()
        } else {
            stopScrollMonitor()
            hideSelectionBorder()
            for panel in host.sessionOverlayPanels {
                panel.sharingType = .readOnly
                panel.ignoresMouseEvents = false
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
            host.sessionRestoreExtraPanels()
        }
    }

    func captureScrollFrame() {
        guard manager.isScrollingCaptureActive else { return }
        guard let host, let screen = host.sessionScreen else { return }
        let selection = host.sessionSelectionRect
        guard selection.width > 2, selection.height > 2 else { return }

        let rect = screenRect(from: selection, screenFrame: screen.frame)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cgImage = await CaptureAreaController.shared.capturePreviewCGImage(rect: rect) {
                self.manager.appendScrollingFrame(cgImage)
            }
        }
    }

    func didUpdateStitchedPreview(_ image: CGImage, totalHeight: Int) {
        host?.sessionDidUpdateStitchedPreview(image, totalHeight: totalHeight)
    }

    func didDetectScrollTooFast() {
        host?.sessionDidDetectScrollTooFast()
    }

    // MARK: - Selection Border

    private func showSelectionBorder() {
        guard let host, let screen = host.sessionScreen ?? NSScreen.main else { return }
        hideSelectionBorder()

        let selRect = screenRect(from: host.sessionSelectionRect, screenFrame: screen.frame)

        let panel = NonKeyPanel(
            contentRect: selRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
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

    // MARK: - Scroll Event Monitoring

    private func startScrollMonitor() {
        stopScrollMonitor()
        updateScrollThreshold()
        scrollingGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
        }
        scrollingLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
            return event
        }
    }

    private func stopScrollMonitor() {
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

    private func updateScrollThreshold() {
        let height = max(0, host?.sessionSelectionRect.height ?? 0)
        let dynamic = height * Self.thresholdMultiplier
        scrollingCaptureThreshold = max(Self.thresholdMin, min(Self.thresholdMax, dynamic))
    }

    private func handleScrollEvent(_ event: NSEvent) {
        guard manager.isScrollingCaptureActive else { return }
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
            ? max(Self.preciseScrollMin, scrollingCaptureThreshold * Self.preciseScrollMultiplier)
            : scrollingCaptureThreshold
        scrollingDeltaAccumulator += delta
        if scrollingDeltaAccumulator >= threshold {
            scrollingDeltaAccumulator = 0
            scheduleCaptureIfNeeded()
        }

        if event.phase == .ended || event.momentumPhase == .ended {
            if scrollingDeltaAccumulator > 0 {
                scrollingDeltaAccumulator = 0
                scheduleCaptureIfNeeded()
            }
        }
    }

    private func scheduleCaptureIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - lastCaptureTime >= Self.minCaptureInterval else { return }
        lastCaptureTime = now

        scrollCaptureWorkItem?.cancel()
        scrollCaptureWorkItem = nil

        let workItem = DispatchWorkItem { [weak self] in
            self?.manager.userDidScroll()
        }
        scrollCaptureWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollRenderDelay, execute: workItem)
    }
}

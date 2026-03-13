//
//  AllInOneCaptureOverlay.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import SwiftUI

final class AllInOneOverlayController: NSObject, NSWindowDelegate {
    static let shared = AllInOneOverlayController()

    private var panels: [UInt32: NSPanel] = [:]
    private var selectedScreenId: UInt32?
    private var keyMonitor: Any?

    func show() {
        if !panels.isEmpty {
            updatePanels()
            panels.values.forEach { $0.orderFrontRegardless() }
            NSApp.activate(ignoringOtherApps: true)
            installKeyMonitor()
            return
        }

        let initialScreen = screenForMouse() ?? NSScreen.main
        selectedScreenId = initialScreen.flatMap { screenId(for: $0) }

        for screen in NSScreen.screens {
            createPanel(for: screen)
        }

        panels.values.forEach { $0.orderFrontRegardless() }
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    func hide() {
        panels.values.forEach { $0.orderOut(nil) }
        removeKeyMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        if let panel = notification.object as? NSPanel,
           let id = screenId(for: panel.screen) {
            panels[id] = nil
        }
        if panels.isEmpty {
            removeKeyMonitor()
        }
    }

    private func screenForMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func screenId(for screen: NSScreen?) -> UInt32? {
        guard let screen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else {
            return nil
        }
        return id
    }

    private func createPanel(for screen: NSScreen) {
        let frame = screen.frame
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        if let id = screenId(for: screen) {
            panels[id] = panel
        }

        updatePanel(panel, for: screen)
    }

    private func updatePanels() {
        for screen in NSScreen.screens {
            if let id = screenId(for: screen), let panel = panels[id] {
                updatePanel(panel, for: screen)
            }
        }
    }

    private func selectScreen(id: UInt32) {
        selectedScreenId = id
        updatePanels()
        panels[id]?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updatePanel(_ panel: NSPanel, for screen: NSScreen) {
        let screenIdentifier = screenId(for: screen)
        let isActive = screenIdentifier == selectedScreenId
        let contentView = AllInOneOverlayView(
            isActive: isActive,
            onSelectScreen: { [weak self] in
                if let screenIdentifier {
                    self?.selectScreen(id: screenIdentifier)
                }
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        if let hostingView = panel.contentView as? NSHostingView<AllInOneOverlayView> {
            hostingView.rootView = contentView
        } else {
            panel.contentView = NSHostingView(rootView: contentView)
        }
    }

    private func installKeyMonitor() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private enum CaptureMode: String, CaseIterable {
    case area = "Area"
    case fullscreen = "Fullscreen"
    case window = "Window"
    case scrolling = "Scrolling"
    case timer = "Timer"
    case ocr = "OCR"
    case recording = "Recording"

    var systemImage: String {
        switch self {
        case .area: return "crop"
        case .fullscreen: return "rectangle.inset.fill"
        case .window: return "macwindow.on.rectangle"
        case .scrolling: return "arrow.up.and.down.square"
        case .timer: return "timer"
        case .ocr: return "text.viewfinder"
        case .recording: return "record.circle"
        }
    }
}

private struct AllInOneOverlayView: View {
    let isActive: Bool
    let onSelectScreen: () -> Void
    let onClose: () -> Void

    @State private var selectedMode: CaptureMode = .area
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var committedSelection: CGRect?
    @State private var isMovingSelection = false
    @State private var moveStartLocation: CGPoint?
    @State private var moveStartRect: CGRect?
    @State private var isFullscreen = false
    @State private var lastSelectionBeforeFullscreen: CGRect?
    @State private var pendingPreviousSelection: CGRect?
    @State private var isDrawingNewSelection = false

    var body: some View {
        ZStack {
            Color.black.opacity(isActive ? 0.25 : 0.15)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    if isActive, let selectionRect = activeSelection {
                        ZStack {
                            Color.black.opacity(0.45)
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: selectionRect.size.width, height: selectionRect.size.height)
                                .position(x: selectionRect.midX, y: selectionRect.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()

                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                            .frame(width: selectionRect.size.width, height: selectionRect.size.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }

                    if isActive, let selectionRect = activeSelection {
                        toolbar(selectionRect: selectionRect, size: proxy.size)
                            .position(x: selectionRect.midX, y: toolbarY(for: selectionRect, in: proxy.size))
                            .zIndex(2)
                    } else {
                        Button(action: onSelectScreen) {
                            Label("Select This Screen", systemImage: "display")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.22))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .zIndex(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isActive {
                        onSelectScreen()
                    }
                }
                .onAppear {
                    if isActive, committedSelection == nil {
                        committedSelection = defaultSelection(in: proxy.size)
                    }
                }
                .onChange(of: isActive) { active in
                    if active, committedSelection == nil {
                        committedSelection = defaultSelection(in: proxy.size)
                    }
                }
                .onChange(of: proxy.size) { newSize in
                    if committedSelection == nil && isActive {
                        committedSelection = defaultSelection(in: newSize)
                    } else if let current = committedSelection {
                        committedSelection = clamp(rect: current, in: newSize)
                    }
                    if isFullscreen {
                        committedSelection = CGRect(origin: .zero, size: newSize)
                    }
                }
                .gesture(
                    isActive
                        ? DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let location = value.location
                                if let currentSelection = committedSelection, currentSelection.contains(location) {
                                    if !isMovingSelection {
                                        isMovingSelection = true
                                        moveStartLocation = location
                                        moveStartRect = currentSelection
                                    }
                                    if let moveStartLocation, let moveStartRect {
                                        let dx = location.x - moveStartLocation.x
                                        let dy = location.y - moveStartLocation.y
                                        let moved = moveStartRect.offsetBy(dx: dx, dy: dy)
                                        committedSelection = clamp(rect: moved, in: proxy.size)
                                    }
                                    return
                                }

                                if dragStart == nil {
                                    pendingPreviousSelection = committedSelection
                                    dragStart = value.startLocation
                                    dragCurrent = location
                                    isDrawingNewSelection = false
                                    return
                                }

                                dragCurrent = location

                                if let start = dragStart {
                                    let dx = location.x - start.x
                                    let dy = location.y - start.y
                                    let distance = hypot(dx, dy)
                                    if distance > 4 {
                                        isDrawingNewSelection = true
                                        committedSelection = nil
                                    }
                                }
                            }
                            .onEnded { _ in
                                if isMovingSelection {
                                    isMovingSelection = false
                                    moveStartLocation = nil
                                    moveStartRect = nil
                                } else if isDrawingNewSelection, let selectionRect {
                                    committedSelection = selectionRect
                                    isFullscreen = false
                                } else if let pendingPreviousSelection {
                                    committedSelection = pendingPreviousSelection
                                }
                                pendingPreviousSelection = nil
                                dragStart = nil
                                dragCurrent = nil
                                isDrawingNewSelection = false
                            }
                        : nil
                )
            }
        }
        .onExitCommand { onClose() }
    }

    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        let origin = CGPoint(x: min(start.x, current.x), y: min(start.y, current.y))
        let size = CGSize(width: abs(start.x - current.x), height: abs(start.y - current.y))
        guard size.width > 4, size.height > 4 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private var activeSelection: CGRect? {
        if isDrawingNewSelection {
            return selectionRect
        }
        return committedSelection
    }

    private func defaultSelection(in size: CGSize) -> CGRect {
        let width = min(720, size.width * 0.7)
        let height = min(420, size.height * 0.6)
        let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2 - 20)
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func toolbarY(for selection: CGRect, in size: CGSize) -> CGFloat {
        let topCandidate = selection.minY - 46
        let bottomCandidate = selection.maxY + 40
        let centerCandidate = selection.midY
        let safeTop: CGFloat = 24
        let safeBottom = size.height - 24

        if topCandidate >= safeTop && topCandidate <= safeBottom {
            return topCandidate
        }
        if bottomCandidate >= safeTop && bottomCandidate <= safeBottom {
            return bottomCandidate
        }
        return max(safeTop, min(centerCandidate, safeBottom))
    }

    private func clamp(rect: CGRect, in size: CGSize) -> CGRect {
        var newRect = rect
        if newRect.origin.x < 0 { newRect.origin.x = 0 }
        if newRect.origin.y < 0 { newRect.origin.y = 0 }
        if newRect.maxX > size.width { newRect.origin.x = max(0, size.width - newRect.width) }
        if newRect.maxY > size.height { newRect.origin.y = max(0, size.height - newRect.height) }
        return newRect
    }

    private func toolbar(selectionRect: CGRect, size: CGSize) -> some View {
        let width = Int(selectionRect.width.rounded())
        let height = Int(selectionRect.height.rounded())

        return HStack(spacing: 10) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(selectedMode == mode ? Color.white : Color.white.opacity(0.7))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selectedMode == mode ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 22)
                .overlay(Color.white.opacity(0.2))

            Button {
                if isFullscreen {
                    isFullscreen = false
                    if let lastSelectionBeforeFullscreen {
                        committedSelection = lastSelectionBeforeFullscreen
                    }
                    lastSelectionBeforeFullscreen = nil
                } else {
                    isFullscreen = true
                    lastSelectionBeforeFullscreen = committedSelection
                    committedSelection = CGRect(origin: .zero, size: size)
                }
            } label: {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)

            Text("\(width) × \(height)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

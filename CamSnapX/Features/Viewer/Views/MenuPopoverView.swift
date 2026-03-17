//
//  MenuPopoverView.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuPopoverView: View {
    @ObservedObject var historyStore: CaptureHistoryStore
    @Binding var draggedImage: NSImage?
    @Binding var isDragOver: Bool
    @Binding var hasPreviousArea: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBlurView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isDragOver ? Color.blue.opacity(0.85) : Color.white.opacity(0.12), lineWidth: isDragOver ? 3 : 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                MenuRowButton("All-In-One", systemImage: "sparkles.rectangle.stack") {
                    AllInOneOverlayController.shared.show()
                    onDismiss()
                }
                MenuRowButton("Capture Area", systemImage: "crop") {
                    CaptureAreaController.shared.startCapture()
                    onDismiss()
                }
                if hasPreviousArea {
                    MenuRowButton("Capture Previous Area", systemImage: "arrow.uturn.backward.circle") {
                        CaptureAreaController.shared.capturePreviousArea()
                        onDismiss()
                    }
                }
                MenuRowButton("Capture Fullscreen", systemImage: "rectangle.inset.fill") {
                    CaptureAreaController.shared.captureFullScreen()
                    onDismiss()
                }
                MenuRowButton("Capture Window", systemImage: "macwindow.on.rectangle") {
                    CaptureAreaController.shared.captureWindow()
                    onDismiss()
                }
                MenuRowButton("Scrolling Capture", systemImage: "arrow.up.and.down.square") {
                    ScrollingCaptureOverlayController.shared.show()
                    onDismiss()
                }
                MenuRowButton("Capture Text (OCR)", systemImage: "text.viewfinder") { }
                MenuRowButton("Record Screen", systemImage: "record.circle") { }
                menuDivider
                MenuRowButton("Hide Desktop Icons", systemImage: "eye.slash") { }
                menuDivider
                MenuRowButton("Open...", systemImage: "folder") { }
                MenuRowButton("Pin to the Screen...", systemImage: "pin") { }
                menuDivider
                MenuRowButton("Capture History...", systemImage: "clock.arrow.circlepath") {
                    CaptureHistoryPanelController.shared.show(store: historyStore)
                    onDismiss()
                }
                MenuRowButton("About CamSnapX...", systemImage: "info.circle") {
                    SettingsPanelController.shared.show(tab: .about)
                    onDismiss()
                }
                MenuRowButton("Check for Updates...", systemImage: "arrow.triangle.2.circlepath") { }
                MenuRowButton("Settings...", systemImage: "gearshape") {
                    SettingsPanelController.shared.show(tab: .general)
                    onDismiss()
                }
                menuDivider
                MenuRowButton("Quit", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
        .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            Group {
                if let image = draggedImage {
                    DragPreviewView(image: image, isVisible: $draggedImage)
                }
            }
        )
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    if let image = object as? NSImage {
                        DispatchQueue.main.async {
                            self.draggedImage = image
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let image = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            self.draggedImage = image
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

//
//  ContentView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.controlActiveState) private var controlActiveState
    @StateObject private var historyStore = CaptureHistoryStore.shared
    @State private var draggedImage: NSImage? = nil
    @State private var isDragOver = false
    @State private var hasPreviousArea = CaptureAreaController.shared.hasPreviousArea

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isDragOver ? Color.blue.opacity(0.8) : Color.white.opacity(0.15), lineWidth: isDragOver ? 3 : 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)

                MenuRowButton("All-In-One", systemImage: "sparkles.rectangle.stack") {
                    AllInOneOverlayController.shared.show()
                    dismiss()
                }
                MenuRowButton("Capture Area", systemImage: "crop") {
                    CaptureAreaController.shared.startCapture()
                    dismiss()
                }
                if hasPreviousArea {
                    MenuRowButton("Capture Previous Area", systemImage: "arrow.uturn.backward.circle") {
                        CaptureAreaController.shared.capturePreviousArea()
                        dismiss()
                    }
                }
                MenuRowButton("Capture Fullscreen", systemImage: "rectangle.inset.fill") {
                    CaptureAreaController.shared.captureFullScreen()
                    dismiss()
                }
                MenuRowButton("Capture Window", systemImage: "macwindow.on.rectangle") {
                    CaptureAreaController.shared.captureWindow()
                    dismiss()
                }
                MenuRowButton("Scrolling Capture", systemImage: "arrow.up.and.down.square") {
                    ScrollingCaptureOverlayController.shared.show()
                    dismiss()
                }
                MenuRowButton("Capture Text (OCR)", systemImage: "text.viewfinder") { }
                MenuRowButton("Record Screen", systemImage: "record.circle") { }
                Divider()
                MenuRowButton("Hide Desktop Icons", systemImage: "eye.slash") { }
                Divider()
                MenuRowButton("Open...", systemImage: "folder") { }
                MenuRowButton("Pin to the Screen...", systemImage: "pin") { }
                Divider()
                MenuRowButton("Capture History...", systemImage: "clock.arrow.circlepath") {
                    CaptureHistoryPanelController.shared.show(store: historyStore)
                    dismiss()
                }
                MenuRowButton("About CamSnapX...", systemImage: "info.circle") { }
                MenuRowButton("Check for Updates...", systemImage: "arrow.triangle.2.circlepath") { }
                MenuRowButton("Settings...", systemImage: "gearshape") { }
                Divider()
                MenuRowButton("Quit", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(width: 220)
        .onExitCommand {
            dismiss()
        }
        .onChange(of: controlActiveState) {
            if controlActiveState == .inactive {
                dismiss()
            }
        }
        .onAppear {
            hasPreviousArea = CaptureAreaController.shared.hasPreviousArea
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .captureAreaDidUpdate) {
                hasPreviousArea = CaptureAreaController.shared.hasPreviousArea
            }
        }
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

#Preview {
    ContentView()
        .frame(width: 300, height: 600)
        .padding()
}

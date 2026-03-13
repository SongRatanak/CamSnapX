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

                MenuRowButton("All-In-One", systemImage: "sparkles.rectangle.stack") { }
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
                MenuRowButton("Scrolling Capture", systemImage: "arrow.up.and.down.square") { }
                MenuRowButton("Self-Timer", systemImage: "timer") { }
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
            if controlActiveState != .key {
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

private struct DragPreviewView: View {
    let image: NSImage
    @Binding var isVisible: NSImage?

    @State private var dragOffset = CGSize.zero
    @State private var accumulatedOffset = CGSize.zero

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isVisible = nil
                }

            VStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 400, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    Button("Close") {
                        isVisible = nil
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding()
                }
            }
            .padding()
            .offset(x: accumulatedOffset.width + dragOffset.width,
                    y: accumulatedOffset.height + dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        accumulatedOffset.width += value.translation.width
                        accumulatedOffset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
        }
    }
}

private struct SelectionBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .selection
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    }
}

private struct MenuRowButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isHovering ? Color(nsColor: .selectedMenuItemTextColor) : Color(nsColor: .controlTextColor))
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Group {
                if isHovering {
                    SelectionBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Color.clear
                }
            }
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 300, height: 600)
        .padding()
}

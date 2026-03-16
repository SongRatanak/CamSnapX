//
//  CapturePreviewPanel.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers


final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct CapturePreviewView: View {
    @State var image: NSImage
    let fileURL: URL?
    let onClose: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Bool
    let windowProvider: () -> NSWindow?

    @State private var isHovering = false
    @State private var savedFeedback = false
    @State private var isDismissing = false

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 160, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipped()
                .onDrag {
                    dismissWithAnimation()
                    return makeDragItemProvider()
                }

            if isHovering {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(width: 160, height: 120)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 160, height: 120)
                    .allowsHitTesting(false)

                VStack(spacing: 6) {
                    Button("Copy") {
                        onCopy()
                        dismissWithAnimation()
                    }

                    Button(savedFeedback ? "Saved!" : "Save") {
                        if onSave() {
                            savedFeedback = true
                            dismissWithAnimation()
                        }
                    }
                    .disabled(savedFeedback)
                }
                .foregroundStyle(Color.white)
            }

            // Close button always on top
            VStack {
                HStack {
                    Button(action: dismissWithAnimation) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
                    Spacer()
                    Button(action: openImageViewer) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
                }
                Spacer()
            }
            .padding(8)
            .frame(width: 160, height: 120)
        }
        .padding(6)
        .allowsHitTesting(!isDismissing)
        .onTapGesture(count: 2) {
            openImageViewer()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func openImageViewer() {
        let viewer = ImageViewerController(image: image, fileURL: fileURL)
        viewer.onImageUpdated = { newImage in
            image = newImage
        }
        ImageViewerController.activeViewers.append(viewer)
        viewer.show()
    }

    private func dismissWithAnimation() {
        guard !isDismissing else { return }
        isDismissing = true

        // Capture window reference before onClose removes it from tracking
        let window = windowProvider()

        // Notify immediately so sibling panels relayout right away
        onClose()

        // Fade + scale down
        guard let window else { return }

        let currentFrame = window.frame
        let targetFrame = NSRect(
            x: currentFrame.midX - (currentFrame.width * 0.92) / 2,
            y: currentFrame.midY - (currentFrame.height * 0.92) / 2,
            width: currentFrame.width * 0.92,
            height: currentFrame.height * 0.92
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func makeDragItemProvider() -> NSItemProvider {
        let dragURL: URL?

        if let pngData = pngData(from: image) {
            dragURL = writeTemporaryPNG(pngData, filename: dragFilename())
        } else {
            dragURL = fileURL
        }

        let provider: NSItemProvider
        if let dragURL {
            provider = NSItemProvider(contentsOf: dragURL) ?? NSItemProvider(object: dragURL as NSURL)
            provider.suggestedName = dragURL.lastPathComponent
        } else {
            provider = NSItemProvider(object: image)
            provider.suggestedName = dragFilename()
        }

        if let pngData = pngData(from: image) {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier,
                                                visibility: .all) { completion in
                completion(pngData, nil)
                return nil
            }
        }

        return provider
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func writeTemporaryPNG(_ data: Data, filename: String) -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func dragFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        return "CamSnapX \(timestamp).png"
    }
}

#Preview {
    CapturePreviewView(
        image: NSImage(),
        fileURL: nil,
        onClose: {},
        onCopy: {},
        onSave: { true },
        windowProvider: { nil }
    )
}

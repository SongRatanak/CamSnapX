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

struct CapturePreviewView: View {
    let image: NSImage
    let fileURL: URL?
    let onClose: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Bool

    @State private var isHovering = false
    @State private var savedFeedback = false
    @State private var isDismissing = false

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .clipped()
                .onDrag {
                    dismissWithAnimation()
                    return makeDragItemProvider()
                }

            if isHovering {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.9))
                    .frame(width: 180, height: 140)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        Button(action: dismissWithAnimation) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(6)

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
        }
        .padding(6)
        .offset(x: isDismissing ? -240 : 0)
        .opacity(isDismissing ? 0 : 1)
        .animation(.easeInOut(duration: 0.25), value: isDismissing)
        .allowsHitTesting(!isDismissing)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func dismissWithAnimation() {
        guard !isDismissing else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            isDismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onClose()
        }
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
        onSave: { true }
    )
}

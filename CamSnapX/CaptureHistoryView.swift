//
//  CaptureHistoryView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI
import AppKit

struct CaptureHistoryView: View {
    @ObservedObject var store: CaptureHistoryStore
    @State private var selectedItem: CaptureHistoryItem?

    var body: some View {
        HStack(spacing: 0) {
            // List Panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Capture History")
                        .font(.headline)
                        .padding()
                    Spacer()
                    Button(action: { store.clear() }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .padding()
                }
                .borderBottom()

                // List
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.items) { item in
                            CaptureHistoryListItem(
                                item: item,
                                isSelected: selectedItem?.id == item.id,
                                action: { selectedItem = item }
                            )
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 220)

            Divider()

            // Detail Panel
            if let selectedItem = selectedItem {
                CaptureDetailView(item: selectedItem)
            } else {
                VStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a capture")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            selectedItem = store.items.first
        }
    }
}

private struct CaptureHistoryListItem: View {
    let item: CaptureHistoryItem
    let isSelected: Bool
    let action: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Thumbnail
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .cornerRadius(6)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 50, height: 50)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileURL.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color(nsColor: .selectedControlColor) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onDrag {
            NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider()
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: item.fileURL) {
                DispatchQueue.main.async {
                    thumbnail = image
                }
            }
        }
    }
}

private struct CaptureDetailView: View {
    let item: CaptureHistoryItem
    @State private var image: NSImage?
    @State private var fileSize: String = "—"

    var body: some View {
        VStack(spacing: 16) {
            // Image Preview
            ScrollView([.horizontal, .vertical]) {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDrag {
                            NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider()
                        }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            // Metadata
            VStack(alignment: .leading, spacing: 12) {
                MetadataRow(label: "Filename", value: item.fileURL.lastPathComponent)
                MetadataRow(label: "Path", value: item.fileURL.path)
                MetadataRow(label: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .standard))
                MetadataRow(label: "Size", value: fileSize)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { NSPasteboard.general.copy(image) }) {
                        Label("Copy Image", systemImage: "doc.on.doc")
                    }

                    Button(action: { NSWorkspace.shared.open(item.fileURL) }) {
                        Label("Open", systemImage: "arrow.up.right")
                    }

                    Button(action: { NSWorkspace.shared.selectFile(item.fileURL.path, inFileViewerRootedAtPath: "") }) {
                        Label("Reveal", systemImage: "folder")
                    }

                    Spacer()
                }
                .frame(height: 32)
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            loadImage()
            loadFileSize()
        }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: item.fileURL) {
                DispatchQueue.main.async {
                    self.image = image
                }
            }
        }
    }

    private func loadFileSize() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: item.fileURL.path),
               let size = attributes[.size] as? Int {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useKB, .useMB, .useGB]
                formatter.countStyle = .file
                DispatchQueue.main.async {
                    self.fileSize = formatter.string(fromByteCount: Int64(size))
                }
            }
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

private extension View {
    func borderBottom() -> some View {
        self.overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private extension NSPasteboard {
    func copy(_ image: NSImage?) {
        guard let image = image else { return }
        clearContents()
        setData(image.pngData(), forType: .png)
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

#Preview {
    CaptureHistoryView(store: CaptureHistoryStore.shared)
}

//
//  CaptureHistoryPanelView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

private enum HistoryTab: String, CaseIterable {
    case all = "All"
    case screenshots = "Screenshots"
    case videos = "Videos"
    case gifs = "GIFs"
}

struct CaptureHistoryPanelView: View {
    @ObservedObject var store: CaptureHistoryStore

    @State private var selectedTab: HistoryTab = .all

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.16, blue: 0.52),
                            Color(red: 0.10, green: 0.11, blue: 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                header
                tabs
                historyStrip
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Text("Capture History")
                .font(.custom("Avenir Next Demi Bold", size: 16))
                .foregroundStyle(.white)

            Spacer()

            Menu {
                Button(action: { store.retentionDays = nil }) {
                    retentionLabel("Never", isSelected: store.retentionDays == nil)
                }
                Button(action: { store.retentionDays = 1 }) {
                    retentionLabel("1 day", isSelected: store.retentionDays == 1)
                }
                Button(action: { store.retentionDays = 3 }) {
                    retentionLabel("3 days", isSelected: store.retentionDays == 3)
                }
                Button(action: { store.retentionDays = 7 }) {
                    retentionLabel("1 week", isSelected: store.retentionDays == 7)
                }
                Button(action: { store.retentionDays = 30 }) {
                    retentionLabel("1 month", isSelected: store.retentionDays == 30)
                }
                Divider()
                Button(action: { store.clearWithConfirmation() }) {
                    Text("Clear History…")
                        .foregroundStyle(.red)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
        }
    }

    private func retentionLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(HistoryTab.allCases, id: \.self) { tab in
                Button(tab.rawValue) {
                    selectedTab = tab
                }
                .buttonStyle(.plain)
                .font(.custom("Avenir Next Demi Bold", size: 12))
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(selectedTab == tab ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                )
                .foregroundStyle(.white)
            }
        }
    }

    private var historyStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(filteredItems) { item in
                    HistoryCard(item: item) {
                        CaptureAreaController.shared.showPreview(for: item.fileURL)
                    }
                }

                if filteredItems.isEmpty {
                    EmptyHistoryCard()
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var filteredItems: [CaptureHistoryItem] {
        switch selectedTab {
        case .all:
            return store.items
        case .screenshots:
            return store.items.filter { $0.fileURL.pathExtension.lowercased() == "png" }
        case .videos:
            return store.items.filter { ["mov", "mp4"].contains($0.fileURL.pathExtension.lowercased()) }
        case .gifs:
            return store.items.filter { $0.fileURL.pathExtension.lowercased() == "gif" }
        }
    }
}

private struct HistoryCard: View {
    let item: CaptureHistoryItem
    let onRestore: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 170, height: 102)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 170, height: 102)
                }

                if isHovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 170, height: 102)

                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                            .font(.custom("Avenir Next Demi Bold", size: 11))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }

            Text(relativeDateString(from: item.createdAt))
                .font(.custom("Avenir Next Medium", size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
        .onAppear { loadThumbnail() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
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

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct EmptyHistoryCard: View {
    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 170, height: 102)
                .overlay(
                    Text("No items")
                        .font(.custom("Avenir Next Medium", size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                )

            Text("Capture something")
                .font(.custom("Avenir Next Medium", size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

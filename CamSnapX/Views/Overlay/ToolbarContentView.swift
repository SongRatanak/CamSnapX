//
//  ToolbarContentView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

enum ToolbarAction {
    case area, fullscreen, window, scrolling, timer, ocr, recording
}

struct ToolbarContentView: View {
    let onAction: (ToolbarAction) -> Void
    var selectionWidth: Int = 0
    var selectionHeight: Int = 0
    var onSizeChanged: ((Int, Int) -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var isUserEditing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                SegmentButton(icon: "crop", label: "Area") { onAction(.area) }
                segmentDivider()
                SegmentButton(icon: "desktopcomputer", label: "Fullscreen") { onAction(.fullscreen) }
                segmentDivider()
                SegmentButton(icon: "macwindow", label: "Window") { onAction(.window) }
                segmentDivider()
                SegmentButton(icon: "arrow.down.to.line", label: "Scrolling") { onAction(.scrolling) }
                segmentDivider()
                SegmentButton(icon: "timer", label: "Timer") { onAction(.timer) }
                segmentDivider()
                SegmentButton(icon: "text.viewfinder", label: "OCR") { onAction(.ocr) }
                segmentDivider()
                SegmentButton(icon: "video", label: "Recording") { onAction(.recording) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )

            if selectionWidth > 0 && selectionHeight > 0 {
                SizeInputView(
                    width: selectionWidth,
                    height: selectionHeight,
                    onSizeChanged: onSizeChanged,
                    onToggleFullscreen: onToggleFullscreen,
                    isUserEditing: isUserEditing
                )
            }
        }
        .frame(height: 56)
        .environment(\.colorScheme, .dark)
    }

    private struct SegmentButton: View {
        let icon: String
        let label: String
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(isHovering ? 1.0 : 0.8))
                .frame(width: 62, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? .white.opacity(0.12) : .white.opacity(0.001))
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
    }

    private func segmentDivider() -> some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }
}

#Preview {
    ToolbarContentView(onAction: { _ in }, selectionWidth: 720, selectionHeight: 220)
        .frame(width: 680, height: 56)
        .background(.black)
}

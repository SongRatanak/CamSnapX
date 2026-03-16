//
//  ToolbarContentView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import Combine
import SwiftUI

enum ToolbarAction {
    case area, fullscreen, window, scrolling, timer, ocr, recording
}

enum AspectRatioPreset: Hashable {
    case freeform
    case ratio(Double, Double)

    var label: String {
        switch self {
        case .freeform: return "Freeform"
        case .ratio(1, 1): return "1 : 1 (Square)"
        case .ratio(5, 4): return "5 : 4 (10 : 8)"
        case .ratio(4, 3): return "4 : 3"
        case .ratio(7, 5): return "7 : 5"
        case .ratio(3, 2): return "3 : 2 (6 : 4)"
        case .ratio(16, 10): return "16 : 10"
        case .ratio(16, 9): return "16 : 9"
        case .ratio(1.85, 1): return "1.85 : 1"
        case .ratio(2.35, 1): return "2.35 : 1"
        case .ratio(4, 5): return "4 : 5"
        case .ratio(2, 3): return "2 : 3"
        case .ratio(9, 16): return "9 : 16"
        case let .ratio(w, h): return "\(w) : \(h)"
        }
    }

    /// Returns width / height as a CGFloat, or nil for freeform.
    var value: CGFloat? {
        switch self {
        case .freeform: return nil
        case let .ratio(w, h): return CGFloat(w) / CGFloat(h)
        }
    }

    static let landscape: [AspectRatioPreset] = [
        .ratio(1, 1),
        .ratio(5, 4),
        .ratio(4, 3),
        .ratio(7, 5),
        .ratio(3, 2),
        .ratio(16, 10),
        .ratio(16, 9),
        .ratio(1.85, 1),
        .ratio(2.35, 1),
    ]

    static let portrait: [AspectRatioPreset] = [
        .ratio(4, 5),
        .ratio(2, 3),
        .ratio(9, 16),
    ]
}

final class ToolbarModel: ObservableObject {
    @Published var selectionWidth: Int = 0
    @Published var selectionHeight: Int = 0
    @Published var isUserEditing: Bool = false
    @Published var aspectRatio: AspectRatioPreset = .freeform
}

struct ToolbarContentView: View {
    let onAction: (ToolbarAction) -> Void
    @ObservedObject var model: ToolbarModel
    var onSizeChanged: ((Int, Int) -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var onAspectRatioChanged: ((AspectRatioPreset) -> Void)?

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

            if model.selectionWidth > 0 && model.selectionHeight > 0 {
                SizeInputView(
                    width: model.selectionWidth,
                    height: model.selectionHeight,
                    onSizeChanged: onSizeChanged,
                    onToggleFullscreen: onToggleFullscreen,
                    onAspectRatioChanged: onAspectRatioChanged,
                    isUserEditing: model.isUserEditing,
                    aspectRatio: model.aspectRatio
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
    ToolbarContentView(onAction: { _ in }, model: {
        let m = ToolbarModel()
        m.selectionWidth = 720
        m.selectionHeight = 220
        return m
    }())
    .frame(width: 680, height: 56)
    .background(.black)
}

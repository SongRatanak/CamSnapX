//
//  ScrollingCaptureShelfView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import Combine
import SwiftUI

final class ScrollingCaptureViewModel: ObservableObject {
    @Published var previewImage: NSImage?
    @Published var selectionSize: CGSize = .zero

    var canStart: Bool {
        selectionSize.width > 2 && selectionSize.height > 2
    }

    var selectionLabel: String {
        guard canStart else { return "" }
        return "\(Int(selectionSize.width)) x \(Int(selectionSize.height))"
    }
}

struct ScrollingCaptureShelfView: View {
    @ObservedObject var model: ScrollingCaptureViewModel
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Drag to select the scroll area", systemImage: "crop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                if !model.selectionLabel.isEmpty {
                    Text(model.selectionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button(action: onStart) {
                    Text("Start Capture")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(model.canStart ? Color.white : Color.white.opacity(0.35))
                        )
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(!model.canStart)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                if let image = model.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    Text("Preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 150, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .padding(12)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    ScrollingCaptureShelfView(model: ScrollingCaptureViewModel(), onStart: {})
        .frame(width: 320)
        .background(.black)
}

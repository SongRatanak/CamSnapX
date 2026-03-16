//
//  ScrollingCaptureControlView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import Combine
import AppKit
import SwiftUI

final class ScrollingCaptureControlModel: ObservableObject {
    @Published var previewImage: NSImage?
    @Published var capturedHeight: Int = 0
}

struct ScrollingCaptureControlView: View {
    let onCancel: () -> Void
    let onDone: () -> Void
    let showProgress: Bool
    @ObservedObject var model: ScrollingCaptureControlModel

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                if let image = model.previewImage {
                    GeometryReader { geo in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "scroll")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("Scrolling…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 260, height: 180)
            .padding(.top, 10)
            .padding(.horizontal, 10)

            if showProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 260, height: 4)
            }

            if model.capturedHeight > 0 {
                Text("\(model.capturedHeight)px")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text("Scroll slowly for best results")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 8) {
                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                )
                .foregroundStyle(.white)
                .buttonStyle(.plain)

                Button("Done") {
                    onDone()
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                )
                .foregroundStyle(.black)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .environment(\.colorScheme, .dark)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }
}

#Preview {
    ScrollingCaptureControlView(
        onCancel: {}, onDone: {}, showProgress: true,
        model: ScrollingCaptureControlModel()
    )
    .background(.black)
}

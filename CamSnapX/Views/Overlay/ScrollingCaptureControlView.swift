//
//  ScrollingCaptureControlView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

struct ScrollingCaptureControlView: View {
    let onCancel: () -> Void
    let onDone: () -> Void
    let showProgress: Bool

    var body: some View {
        VStack(spacing: 8) {
            if showProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(height: 4)
                    .padding(.horizontal, 10)
            }
            
            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                )
                .foregroundStyle(.black)
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    ScrollingCaptureControlView(onCancel: {}, onDone: {}, showProgress: true)
        .background(.black)
}

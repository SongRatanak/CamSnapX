//
//  ScrollingCaptureShelfView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import Combine
import SwiftUI

final class ScrollingCaptureViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    var selectionSize: CGSize = .zero {
        didSet { objectWillChange.send() }
    }

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

                Text("Preview appears after capture starts.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

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

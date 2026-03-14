//
//  SizeInputView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

struct SizeInputView: View {
    let width: Int
    let height: Int
    var onSizeChanged: ((Int, Int) -> Void)?
    var onToggleFullscreen: (() -> Void)?
    var isUserEditing: Bool = false

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @FocusState private var widthFocused: Bool
    @FocusState private var heightFocused: Bool
    @State private var hoveringToggle = false
    @State private var hoveringCrop = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("W", text: $widthText)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 56)
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(widthFocused ? 0.18 : 0.1))
                )
                .focused($widthFocused)

            Text("×")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))

            TextField("H", text: $heightText)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 56)
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(heightFocused ? 0.18 : 0.1))
                )
                .focused($heightFocused)

            Button(action: { onToggleFullscreen?() }) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(hoveringToggle ? 0.18 : 0.1))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hoveringToggle = $0 }

            Button(action: {}) {
                HStack(spacing: 2) {
                    Image(systemName: "crop")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(height: 28)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(hoveringCrop ? 0.18 : 0.1))
                )
            }
            .buttonStyle(.plain)
            .onHover { hoveringCrop = $0 }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .onAppear {
            widthText = "\(width)"
            heightText = "\(height)"
        }
        .onChange(of: width) {
            if !isUserEditing {
                widthText = "\(width)"
            }
        }
        .onChange(of: height) {
            if !isUserEditing {
                heightText = "\(height)"
            }
        }
        .onChange(of: isUserEditing) {
            if !isUserEditing {
                widthText = "\(width)"
                heightText = "\(height)"
                widthFocused = false
                heightFocused = false
            }
        }
        .onChange(of: widthText) {
            if widthFocused { applyLiveSize() }
        }
        .onChange(of: heightText) {
            if heightFocused { applyLiveSize() }
        }
    }

    private func applyLiveSize() {
        guard let w = Int(widthText), let h = Int(heightText), w >= 10, h >= 10 else { return }
        onSizeChanged?(w, h)
    }
}

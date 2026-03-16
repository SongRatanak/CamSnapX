//
//  ColorPickerPanelView.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import SwiftUI

struct ColorPickerPanelView: View {
    @Binding var selectedColor: NSColor
    @Binding var isPresented: Bool

    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var opacity: Double = 1
    @State private var hexText: String = "FF0000"

    private let presetColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemTeal, .systemBlue, .systemIndigo, .systemPurple,
        .systemPink, .white, .systemGray, .black
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Left: Color swatches
                swatchColumn

                // Right: Gradient picker + controls
                VStack(spacing: 10) {
                    saturationBrightnessBox
                    hueSlider
                    opacitySlider
                    hexInput
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .environment(\.colorScheme, .dark)
        .frame(width: 300)
        .onAppear { syncFromColor() }
    }

    // MARK: - Swatch Column

    private var swatchColumn: some View {
        VStack(spacing: 6) {
            ForEach(Array(presetColors.enumerated()), id: \.offset) { _, color in
                Button {
                    selectedColor = color.withAlphaComponent(opacity)
                    syncFromColor()
                } label: {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    colorsMatch(color) ? Color.white : Color.white.opacity(0.3),
                                    lineWidth: colorsMatch(color) ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Saturation/Brightness Box

    private var saturationBrightnessBox: some View {
        GeometryReader { geo in
            ZStack {
                // Base hue
                Rectangle().fill(Color(hue: hue, saturation: 1, brightness: 1))
                // White gradient left to right
                LinearGradient(
                    colors: [.white, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                // Black gradient bottom to top
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                // Picker indicator
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(
                        x: saturation * geo.size.width,
                        y: (1 - brightness) * geo.size.height
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        saturation = min(max(value.location.x / geo.size.width, 0), 1)
                        let bVal: Double = 1.0 - value.location.y / geo.size.height
                        brightness = min(max(bVal, 0), 1)
                        applyColor()
                    }
            )
        }
        .frame(height: 120)
    }

    // MARK: - Hue Slider

    private var hueSlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Rainbow gradient
                LinearGradient(
                    colors: (0...6).map { Color(hue: Double($0) / 6.0, saturation: 1, brightness: 1) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Thumb
                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .position(x: hue * geo.size.width, y: geo.size.height / 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(value.location.x / geo.size.width, 0), 1)
                        applyColor()
                    }
            )
        }
        .frame(height: 16)
    }

    // MARK: - Opacity Slider

    private var opacitySlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Checkerboard + color gradient
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: saturation, brightness: brightness).opacity(0),
                        Color(hue: hue, saturation: saturation, brightness: brightness)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Thumb
                Circle()
                    .fill(currentSwiftUIColor)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .position(x: opacity * geo.size.width, y: geo.size.height / 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        opacity = min(max(value.location.x / geo.size.width, 0), 1)
                        applyColor()
                    }
            )
        }
        .frame(height: 16)
    }

    // MARK: - Hex Input

    private var hexInput: some View {
        HStack(spacing: 8) {
            TextField("Hex", text: $hexText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                )
                .frame(width: 80)
                .onSubmit { applyHex() }

            Text("Hex")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            // Alpha label
            Text("\(Int(opacity * 100))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                )
                .frame(width: 44)

            Text("Alpha")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var currentSwiftUIColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity)
    }

    private func syncFromColor() {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        let converted = selectedColor.usingColorSpace(.deviceRGB) ?? selectedColor
        converted.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
        opacity = Double(a)
        hexText = hexString(from: converted)
    }

    private func applyColor() {
        let color = NSColor(
            hue: CGFloat(hue),
            saturation: CGFloat(saturation),
            brightness: CGFloat(brightness),
            alpha: CGFloat(opacity)
        )
        selectedColor = color
        hexText = hexString(from: color)
    }

    private func applyHex() {
        guard let color = NSColor(hexString: hexText) else { return }
        selectedColor = color.withAlphaComponent(CGFloat(opacity))
        syncFromColor()
    }

    private func hexString(from color: NSColor) -> String {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func colorsMatch(_ preset: NSColor) -> Bool {
        guard let c1 = selectedColor.usingColorSpace(.deviceRGB),
              let c2 = preset.usingColorSpace(.deviceRGB) else { return false }
        return abs(c1.redComponent - c2.redComponent) < 0.05
            && abs(c1.greenComponent - c2.greenComponent) < 0.05
            && abs(c1.blueComponent - c2.blueComponent) < 0.05
    }
}

// MARK: - NSColor hex extension

extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgbValue & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

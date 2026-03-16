//
//  AnnotationToolbarView.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import SwiftUI

struct AnnotationToolbarView: View {
    @ObservedObject var state: AnnotationState
    let onSaveAs: () -> Void
    let onDone: () -> Void

    @State private var showColorPicker = false
    @State private var showTextStylePicker = false
    @State private var showLineWidthPicker = false
    @State private var showArrowStylePicker = false
    @State private var hoveredLineWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    // Group 1: File operations (placeholder)
                    toolGroup {
                        toolButton("crop", tool: .crop)
                        toolButton("plus.rectangle.on.rectangle", tool: .copyArea)
                        toolButton("photo.badge.plus", tool: .addImage)
                    }

                    groupDivider()

                    // Group 2: Drawing tools (functional)
                    toolGroup {
                        toolButton("cursorarrow", tool: .cursor)
                        toolButton("rectangle", tool: .rectangle)
                        toolButton("rectangle.fill", tool: .filledRectangle)
                        toolButton("circle", tool: .circle)
                        toolButton("line.diagonal", tool: .line)
                        toolButton("arrow.up.right", tool: .arrow)
                        toolButton("textformat", tool: .text)
                    }

                    groupDivider()

                    // Group 3: Effects (placeholder)
                    toolGroup {
                        toolButton("eye.slash", tool: .blur)
                        toolButton("highlighter", tool: .highlight)
                    }

                    groupDivider()

                    // Group 4: Advanced
                    toolGroup {
                        toolButton("number", tool: .numberedMarker)
                        toolButton("pencil.tip", tool: .pen)
                        toolButton("eraser", tool: .eraser)
                        toolButton("wand.and.stars", tool: .smartAnnotate)
                    }

                    groupDivider()

                    // Color picker button
                    Button {
                        showColorPicker.toggle()
                    } label: {
                        Circle()
                            .fill(Color(nsColor: state.selectedColor))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                            )
                            .overlay(
                                // Dropdown chevron
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(y: 14)
                            )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                        ColorPickerPanelView(
                            selectedColor: $state.selectedColor,
                            isPresented: $showColorPicker
                        )
                    }

                    if state.selectedTool == .rectangle || state.selectedTool == .line || state.selectedTool == .circle || state.selectedTool == .arrow {
                        groupDivider()

                        Button {
                            showLineWidthPicker.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle")
                                    .font(.system(size: 12, weight: .semibold))
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(width: 18, height: max(2, state.lineWidth))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showLineWidthPicker, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Stroke Size")
                                    .font(.system(size: 14, weight: .bold))

                                ForEach([1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0], id: \.self) { width in
                                    let isSelected = Int(state.lineWidth.rounded()) == Int(width)
                                    let isHovering = hoveredLineWidth == width

                                    Button {
                                        state.lineWidth = CGFloat(width)
                                        showLineWidthPicker = false
                                    } label: {
                                        HStack(spacing: 10) {
                                            Rectangle()
                                                .fill(Color.primary)
                                                .frame(width: 22, height: max(2, width))
                                                .clipShape(Capsule())
                                            Text("\(Int(width)) pt")
                                                .font(.system(size: 12, weight: .semibold))
                                            Spacer(minLength: 0)
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                            }
                                        }
                                        .frame(maxWidth: 120, minHeight: 24, alignment: .leading)
                                        .padding(.horizontal, 2)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(isSelected ? Color.accentColor.opacity(0.25) : (isHovering ? Color.primary.opacity(0.12) : Color.clear))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        hoveredLineWidth = hovering ? width : nil
                                    }
                                }
                            }
                            .padding(12)
                            .frame(width: 140)
                        }
                    }

                    if state.selectedTool == .arrow {
                        groupDivider()

                        Button {
                            showArrowStylePicker.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                ArrowStylePreview(style: state.arrowStyle, color: Color(nsColor: state.selectedColor))
                                    .frame(width: 20, height: 14)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showArrowStylePicker, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Arrow Style")
                                    .font(.system(size: 14, weight: .bold))

                                ForEach(ArrowAnnotationStyle.allCases, id: \.self) { style in
                                    let isSelected = state.arrowStyle == style

                                    Button {
                                        state.arrowStyle = style
                                        showArrowStylePicker = false
                                    } label: {
                                        HStack(spacing: 10) {
                                            ArrowStylePreview(style: style, color: Color(nsColor: state.selectedColor))
                                                .frame(width: 36, height: 18)
                                            Text(style.rawValue)
                                                .font(.system(size: 12, weight: .semibold))
                                            Spacer(minLength: 0)
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                            }
                                        }
                                        .frame(maxWidth: 180, minHeight: 24, alignment: .leading)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .frame(width: 220)
                        }
                    }

                    // Text-specific controls (visible when text tool selected)
                    if state.selectedTool == .text {
                        groupDivider()

                        // Font size picker
                        Menu {
                            ForEach([12, 16, 20, 24, 28, 32, 39, 48, 64, 80, 97, 120], id: \.self) { size in
                                Button("\(size) pt") {
                                    state.fontSize = CGFloat(size)
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("\(Int(state.fontSize)) pt")
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)

                // Text style picker
                Button {
                    showTextStylePicker.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text("A")
                            .font(.system(size: 14, weight: .bold, design: designForStyle(state.textStyle)))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTextStylePicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Text")
                                .font(.system(size: 18, weight: .bold))
                            Text(state.textStyle.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 6)

                        ForEach(TextAnnotationStyle.allCases, id: \.self) { style in
                            Button {
                                state.textStyle = style
                                showTextStylePicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    textStylePreview(style)
                                    Text(style.rawValue)
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer(minLength: 0)
                                    if state.textStyle == style {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(state.textStyle == style ? Color.accentColor.opacity(0.25) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(width: 220)
                }
            }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            // Save/Done buttons
            Button("Save as...") {
                onSaveAs()
            }
            .buttonStyle(.bordered)

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Components

    private func toolGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 1) {
            content()
        }
    }

    private func groupDivider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func toolButton(_ systemImage: String, tool: AnnotationTool) -> some View {
        let isSelected = state.selectedTool == tool

        return Button {
            state.selectedTool = tool
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help(toolName(for: tool))
    }

    private struct ArrowStylePreview: View {
        let style: ArrowAnnotationStyle
        let color: Color

        var body: some View {
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let start = CGPoint(x: 2, y: h - 2)
                let end = CGPoint(x: w - 2, y: 2)
                let lineWidth: CGFloat = 2

                ZStack {
                    if style == .curved {
                        let control = curvedControlPoint(from: start, to: end)
                        Path { path in
                            path.move(to: start)
                            path.addQuadCurve(to: end, control: control)
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                        arrowHead(tip: end, tail: control, color: color, filled: false, lineWidth: lineWidth)
                        let mid = quadraticMidpoint(from: start, to: end, control: control)
                        midDot(at: mid, color: color, lineWidth: lineWidth)
                    } else {
                        if style == .fancy {
                            let dx = end.x - start.x
                            let dy = end.y - start.y
                            let distance = max(hypot(dx, dy), 1)
                            let ux = dx / distance
                            let uy = dy / distance
                            let px = -uy
                            let py = ux
                            let shaftWidth = max(1.5, lineWidth * 0.5)
                            let headWidth = max(7.5, lineWidth * 3.1)
                            let headLength = max(8, lineWidth * 4.2)
                            let shaftLength = max(distance - headLength, distance * 0.6)
                            let shaftEnd = CGPoint(x: start.x + ux * shaftLength, y: start.y + uy * shaftLength)
                            let headBase = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
                            let tailLeft = CGPoint(x: start.x + px * shaftWidth, y: start.y + py * shaftWidth)
                            let tailRight = CGPoint(x: start.x - px * shaftWidth, y: start.y - py * shaftWidth)
                            let shaftLeft = CGPoint(x: shaftEnd.x + px * shaftWidth, y: shaftEnd.y + py * shaftWidth)
                            let shaftRight = CGPoint(x: shaftEnd.x - px * shaftWidth, y: shaftEnd.y - py * shaftWidth)
                            let headLeft = CGPoint(x: headBase.x + px * headWidth, y: headBase.y + py * headWidth)
                            let headRight = CGPoint(x: headBase.x - px * headWidth, y: headBase.y - py * headWidth)

                            Path { path in
                                path.move(to: tailLeft)
                                path.addLine(to: shaftLeft)
                                path.addLine(to: headLeft)
                                path.addLine(to: end)
                                path.addLine(to: headRight)
                                path.addLine(to: shaftRight)
                                path.addLine(to: tailRight)
                                path.closeSubpath()
                            }
                            .fill(color)
                        } else {
                            Path { path in
                                path.move(to: start)
                                path.addLine(to: end)
                            }
                            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                            if style == .double {
                                arrowHead(tip: start, tail: end, color: color, filled: false, lineWidth: lineWidth)
                            }

                            let filled = style == .fancy
                            arrowHead(tip: end, tail: start, color: color, filled: filled, lineWidth: lineWidth)

                            if style == .double {
                                let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                                midDot(at: mid, color: color, lineWidth: lineWidth)
                            }
                        }

                    }
                }
            }
        }

        private func arrowHead(tip: CGPoint, tail: CGPoint, color: Color, filled: Bool, lineWidth: CGFloat) -> some View {
            let angle = atan2(tip.y - tail.y, tip.x - tail.x)
            let headLength = max(6, lineWidth * (filled ? 4 : 3))
            let headAngle: CGFloat = filled ? .pi / 5 : .pi / 6

            let left = CGPoint(
                x: tip.x - headLength * cos(angle - headAngle),
                y: tip.y - headLength * sin(angle - headAngle)
            )
            let right = CGPoint(
                x: tip.x - headLength * cos(angle + headAngle),
                y: tip.y - headLength * sin(angle + headAngle)
            )

            return Path { path in
                if filled {
                    path.move(to: tip)
                    path.addLine(to: left)
                    path.addLine(to: right)
                    path.closeSubpath()
                } else {
                    path.move(to: left)
                    path.addLine(to: tip)
                    path.addLine(to: right)
                }
            }
            .fill(filled ? color : .clear)
            .overlay(
                Path { path in
                    if filled {
                        path.move(to: tip)
                        path.addLine(to: left)
                        path.addLine(to: right)
                        path.closeSubpath()
                    } else {
                        path.move(to: left)
                        path.addLine(to: tip)
                        path.addLine(to: right)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            )
        }

        private func curvedControlPoint(from p1: CGPoint, to p2: CGPoint) -> CGPoint {
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let distance = max(hypot(dx, dy), 1)
            let offset = min(10, max(6, distance * 0.2))
            let perp = CGPoint(x: -dy / distance * offset, y: dx / distance * offset)
            return CGPoint(x: mid.x + perp.x, y: mid.y + perp.y)
        }

        private func quadraticMidpoint(from p1: CGPoint, to p2: CGPoint, control: CGPoint) -> CGPoint {
            let t: CGFloat = 0.5
            let oneMinusT = 1 - t
            let x = oneMinusT * oneMinusT * p1.x + 2 * oneMinusT * t * control.x + t * t * p2.x
            let y = oneMinusT * oneMinusT * p1.y + 2 * oneMinusT * t * control.y + t * t * p2.y
            return CGPoint(x: x, y: y)
        }

        private func midDot(at point: CGPoint, color: Color, lineWidth: CGFloat) -> some View {
            let radius = max(3, lineWidth * 1.1)
            return Circle()
                .fill(color)
                .frame(width: radius * 2, height: radius * 2)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: max(1.2, lineWidth * 0.35))
                )
                .position(x: point.x, y: point.y)
        }
    }

    private func textStylePreview(_ style: TextAnnotationStyle) -> some View {
        let design: Font.Design = designForStyle(style)
        let corner = style.backgroundCornerRadius

        return ZStack {
            if style.hasBackground {
                Text("Text")
                    .font(.system(size: 13, weight: .bold, design: design))
                    .foregroundStyle(Color(nsColor: state.selectedColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(Color.white.opacity(0.85))
                    )
            } else if style.isOutlined {
                ZStack {
                    Text("Text")
                        .font(.system(size: 13, weight: .heavy, design: design))
                        .foregroundStyle(.black.opacity(0.7))
                        .offset(x: 0.6, y: 0.6)
                    Text("Text")
                        .font(.system(size: 13, weight: .heavy, design: design))
                        .foregroundStyle(.black.opacity(0.7))
                        .offset(x: -0.6, y: -0.6)
                    Text("Text")
                        .font(.system(size: 13, weight: .heavy, design: design))
                        .foregroundStyle(.black.opacity(0.7))
                        .offset(x: 0.6, y: -0.6)
                    Text("Text")
                        .font(.system(size: 13, weight: .heavy, design: design))
                        .foregroundStyle(.black.opacity(0.7))
                        .offset(x: -0.6, y: 0.6)
                    Text("Text")
                        .font(.system(size: 13, weight: .heavy, design: design))
                        .foregroundStyle(.white)
                }
            } else {
                Text("Text")
                    .font(.system(size: 13, weight: .bold, design: design))
            }
        }
    }

    private func designForStyle(_ style: TextAnnotationStyle) -> Font.Design {
        switch style {
        case .rounded, .roundedBox: return .rounded
        case .mono, .monoBox: return .monospaced
        default: return .default
        }
    }

    private func toolName(for tool: AnnotationTool) -> String {
        switch tool {
        case .crop: return "Crop"
        case .copyArea: return "Copy Area"
        case .addImage: return "Add Image"
        case .cursor: return "Cursor"
        case .rectangle: return "Rectangle"
        case .filledRectangle: return "Filled Rectangle"
        case .circle: return "Circle"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .blur: return "Blur"
        case .highlight: return "Highlight"
        case .numberedMarker: return "Numbered Marker"
        case .pen: return "Pen"
        case .eraser: return "Eraser"
        case .smartAnnotate: return "Smart Annotate"
        }
    }

}

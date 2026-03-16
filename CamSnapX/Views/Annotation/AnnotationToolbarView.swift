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
                        Menu {
                            ForEach(TextAnnotationStyle.allCases, id: \.self) { style in
                                Button {
                                    state.textStyle = style
                                } label: {
                                    HStack {
                                        textStylePreview(style)
                                        Text(style.rawValue)
                                        if state.textStyle == style {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
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

    private func textStylePreview(_ style: TextAnnotationStyle) -> some View {
        let design: Font.Design = designForStyle(style)
        return Text("Text")
            .font(.system(size: 13, weight: .bold, design: design))
            .padding(.horizontal, style.hasBackground ? 4 : 0)
            .padding(.vertical, style.hasBackground ? 2 : 0)
            .background(
                Group {
                    if style.hasBackground {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.2))
                    }
                }
            )
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

//
//  AnnotationTextEditor.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import SwiftUI
import AppKit

// MARK: - NSTextView wrapper (multi-line, supports emoji + Enter for newlines)

struct MultiLineTextView: NSViewRepresentable {
    @Binding var text: String
    var color: NSColor
    var fontSize: CGFloat
    var textStyle: TextAnnotationStyle
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = textStyle.font(ofSize: fontSize)
        textView.textColor = color
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        // Use textContainerInset for padding, let width tracking handle sizing.
        // The NSScrollView frame (set by SwiftUI .frame()) controls the available width.
        // widthTracksTextView = true means the container auto-sizes to:
        //   textView.width - 2 * textContainerInset.width
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.textColor = color
        textView.font = textStyle.font(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: 4, height: 4)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultiLineTextView
        weak var textView: NSTextView?

        init(_ parent: MultiLineTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView {
                parent.text = tv.string
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            // Let Enter/Return pass through for newlines
            return false
        }
    }
}

// MARK: - Text Editor View (CleanShot X style)

struct AnnotationTextEditor: View {
    @Binding var text: String
    let nsColor: NSColor
    let onCommit: () -> Void
    let onCancel: () -> Void
    @Binding var position: CGPoint   // Top-left of text box in view space
    @Binding var fontSize: CGFloat   // View-space font size
    let textStyle: TextAnnotationStyle
    @Binding var boxWidth: CGFloat?  // View-space width override
    var imageToViewScale: CGFloat = 1.0

    private let circleDiameter: CGFloat = 14
    private let squareSize: CGFloat = 10
    private let minBoxWidth: CGFloat = 40
    private let minBoxHeight: CGFloat = 20
    private let emojiHeight: CGFloat = 26
    private let emojiSpacing: CGFloat = 4
    private let textInsetX: CGFloat = 4
    private let textInsetY: CGFloat = 4

    @State private var scaleStartFontSize: CGFloat? = nil
    @State private var scaleStartBoxWidth: CGFloat? = nil
    @State private var scaleStartLocation: CGPoint? = nil
    @State private var widthDragStartWidth: CGFloat? = nil
    @State private var widthDragStartPosX: CGFloat? = nil
    @State private var widthDragStartLocation: CGFloat? = nil
    @State private var moveDragStartPos: CGPoint? = nil
    @State private var moveDragStartLocation: CGPoint? = nil
    @State private var isDraggingHandle = false

    private let coordinateSpaceName = "annotationEditorSpace"

    /// Measure text to compute natural box size
    private var measuredTextSize: CGSize {
        let font = textStyle.font(ofSize: fontSize)
        let displayText = text.isEmpty ? "Type here..." : text
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let constraintW: CGFloat = (boxWidth != nil) ? max(boxWidth! - textInsetX * 2, 1) : CGFloat.greatestFiniteMagnitude
        let rect = (displayText as NSString).boundingRect(
            with: CGSize(width: constraintW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// The effective box width: either user-set boxWidth, or text width + padding, with a minimum
    private var effectiveBoxWidth: CGFloat {
        if let bw = boxWidth {
            return max(bw, minBoxWidth)
        }
        return max(measuredTextSize.width + textInsetX * 2, minBoxWidth)
    }

    /// The effective box height: text height + padding, with a minimum
    private var boxHeight: CGFloat {
        max(measuredTextSize.height + textInsetY * 2, minBoxHeight)
    }

    var body: some View {
        let emojiSection = emojiHeight + emojiSpacing
        let totalHeight = emojiSection + boxHeight
        let offsetX = position.x + effectiveBoxWidth / 2
        let offsetY = position.y + totalHeight / 2 - emojiSection

        ZStack {
            VStack(spacing: emojiSpacing) {
                // Emoji button
                Button {
                    DispatchQueue.main.async {
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: emojiHeight, height: emojiHeight)
                        Image(systemName: "face.smiling.inverse")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                // Text box with dashed border + handles
                ZStack {
                    // Dashed border (also drag-to-move area)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: effectiveBoxWidth, height: boxHeight)
                        .contentShape(Rectangle())
                        .gesture(moveGesture)
                        .overlay(
                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                .foregroundStyle(Color.accentColor)
                        )

                    if textStyle.isOutlined {
                        OutlinedTextView(
                            text: $text,
                            color: nsColor,
                            fontSize: fontSize,
                            textStyle: textStyle,
                            onCancel: onCancel
                        )
                        .frame(width: effectiveBoxWidth, height: boxHeight)
                        .clipped()
                        .background(textBackground)
                        .allowsHitTesting(!isDraggingHandle)
                        .zIndex(1)
                    } else {
                        MultiLineTextView(
                            text: $text,
                            color: nsColor,
                            fontSize: fontSize,
                            textStyle: textStyle,
                            onCancel: onCancel
                        )
                        .frame(width: effectiveBoxWidth, height: boxHeight)
                        .clipped()
                        .background(textBackground)
                        .allowsHitTesting(!isDraggingHandle)
                        .zIndex(1)
                    }

                    // Mid-left circle handle
                    handleCircle(xOffset: -(effectiveBoxWidth / 2), yOffset: 0, isRight: false)
                        .zIndex(2)
                    // Mid-right circle handle
                    handleCircle(xOffset: (effectiveBoxWidth / 2), yOffset: 0, isRight: true)
                        .zIndex(2)
                    // Bottom-right small square handle
                    handleSquare(xOffset: (effectiveBoxWidth / 2), yOffset: (boxHeight / 2))
                        .zIndex(2)
                }
            }
            .position(x: offsetX, y: offsetY)
        }
        .coordinateSpace(name: coordinateSpaceName)
    }

    @ViewBuilder
    private var textBackground: some View {
        if textStyle.hasBackground {
            RoundedRectangle(cornerRadius: textStyle.backgroundCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.85))
        } else {
            EmptyView()
        }
    }

    // MARK: - Handles

    private func handleCircle(xOffset: CGFloat, yOffset: CGFloat, isRight: Bool) -> some View {
        let hitSize = max(circleDiameter + 10, 28)
        return ZStack {
            Color.clear
                .frame(width: hitSize, height: hitSize)
            Circle()
                .fill(Color.white)
                .frame(width: circleDiameter, height: circleDiameter)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
        }
        .contentShape(Rectangle().size(width: hitSize, height: hitSize))
        .highPriorityGesture(widthResizeGesture(isRight: isRight))
        .onHover { isHovering in
            if isHovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .offset(x: xOffset, y: yOffset)
    }

    private func handleSquare(xOffset: CGFloat, yOffset: CGFloat) -> some View {
        let hitSize = max(squareSize + 10, 28)
        return ZStack {
            Color.clear
                .frame(width: hitSize, height: hitSize)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: squareSize, height: squareSize)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 2))
        }
        .contentShape(Rectangle().size(width: hitSize, height: hitSize))
        .highPriorityGesture(scaleGesture)
        .onHover { isHovering in
            if isHovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        .offset(x: xOffset, y: yOffset)
    }

    // MARK: - Gestures

    private var scaleGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if scaleStartFontSize == nil {
                    scaleStartFontSize = fontSize
                    scaleStartBoxWidth = boxWidth ?? effectiveBoxWidth
                    scaleStartLocation = value.startLocation
                    isDraggingHandle = true
                }
                guard let startFont = scaleStartFontSize,
                      let startBox = scaleStartBoxWidth,
                      let startLoc = scaleStartLocation else { return }
                let dx = value.location.x - startLoc.x
                let dy = value.location.y - startLoc.y
                let distance = max(dx, dy)
                let scaleFactor = max(0.5, min(3.0, 1.0 + (distance / 220)))
                fontSize = max(startFont * scaleFactor, 10)
                boxWidth = max(startBox * scaleFactor, minBoxWidth)
            }
            .onEnded { _ in
                scaleStartFontSize = nil
                scaleStartBoxWidth = nil
                scaleStartLocation = nil
                isDraggingHandle = false
            }
    }

    private func widthResizeGesture(isRight: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if widthDragStartWidth == nil {
                    widthDragStartWidth = boxWidth ?? effectiveBoxWidth
                    widthDragStartPosX = position.x
                    widthDragStartLocation = value.startLocation.x
                    isDraggingHandle = true
                }
                guard let startWidth = widthDragStartWidth,
                      let startPosX = widthDragStartPosX,
                      let startLocX = widthDragStartLocation else { return }
                let delta = value.location.x - startLocX
                var newWidth: CGFloat
                if isRight {
                    newWidth = startWidth + delta
                } else {
                    newWidth = startWidth - delta
                }
                newWidth = max(newWidth, minBoxWidth)
                if !isRight {
                    let rightEdge = startPosX + startWidth
                    position.x = rightEdge - newWidth
                }
                boxWidth = newWidth
            }
            .onEnded { _ in
                widthDragStartWidth = nil
                widthDragStartPosX = nil
                widthDragStartLocation = nil
                isDraggingHandle = false
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if moveDragStartPos == nil {
                    moveDragStartPos = position
                    moveDragStartLocation = value.startLocation
                    isDraggingHandle = true
                }
                guard let startPos = moveDragStartPos,
                      let startLoc = moveDragStartLocation else { return }
                position = CGPoint(
                    x: startPos.x + (value.location.x - startLoc.x),
                    y: startPos.y + (value.location.y - startLoc.y)
                )
            }
            .onEnded { _ in
                moveDragStartPos = nil
                moveDragStartLocation = nil
                isDraggingHandle = false
            }
    }

}

// MARK: - Outlined Text View

struct OutlinedTextView: NSViewRepresentable {
    @Binding var text: String
    var color: NSColor
    var fontSize: CGFloat
    var textStyle: TextAnnotationStyle
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let strokeField = NSTextField(labelWithString: text)
        strokeField.isEditable = false
        strokeField.isSelectable = false
        strokeField.drawsBackground = false
        strokeField.isBezeled = false
        strokeField.backgroundColor = .clear
        strokeField.textColor = color
        strokeField.font = textStyle.font(ofSize: fontSize)
        strokeField.alignment = .left

        let fillField = NSTextField(labelWithString: text)
        fillField.isEditable = false
        fillField.isSelectable = false
        fillField.drawsBackground = false
        fillField.isBezeled = false
        fillField.backgroundColor = .clear
        fillField.textColor = color
        fillField.font = textStyle.font(ofSize: fontSize)
        fillField.alignment = .left

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = textStyle.font(ofSize: fontSize)
        textView.textColor = .clear
        textView.insertionPointColor = color
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        // Let width tracking handle sizing from the scroll view frame
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView

        for v in [strokeField, fillField, scrollView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                v.topAnchor.constraint(equalTo: container.topAnchor),
                v.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        context.coordinator.strokeField = strokeField
        context.coordinator.fillField = fillField
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        }

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let strokeField = context.coordinator.strokeField,
              let fillField = context.coordinator.fillField,
              let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }
        strokeField.stringValue = text
        fillField.stringValue = text
        strokeField.textColor = color
        fillField.textColor = color
        strokeField.font = textStyle.font(ofSize: fontSize)
        fillField.font = textStyle.font(ofSize: fontSize)
        textView.font = textStyle.font(ofSize: fontSize)
        textView.insertionPointColor = color
        textView.textContainerInset = NSSize(width: 4, height: 4)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: OutlinedTextView
        weak var strokeField: NSTextField?
        weak var fillField: NSTextField?
        weak var textView: NSTextView?

        init(_ parent: OutlinedTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView {
                parent.text = tv.string
                strokeField?.stringValue = tv.string
                fillField?.stringValue = tv.string
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

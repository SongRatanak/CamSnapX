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
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.string = text

        // Allow Enter to insert newlines (default behavior for NSTextView)
        // Escape handled in delegate

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            // Move cursor to end
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
    @Binding var position: CGPoint   // Center position in view space
    @Binding var fontSize: CGFloat   // View-space font size
    let textStyle: TextAnnotationStyle

    private let padding: CGFloat = 10
    private let circleDiameter: CGFloat = 14
    private let squareSize: CGFloat = 10

    @GestureState private var scaleStart: CGFloat? = nil

    /// Measure text to auto-fit the box
    private var textSize: CGSize {
        let font = textStyle.font(ofSize: fontSize)
        let displayText = text.isEmpty ? "Type here..." : text
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let boundingRect = (displayText as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return CGSize(
            width: max(ceil(boundingRect.width) + 12, 60),
            height: max(ceil(boundingRect.height) + 4, 24)
        )
    }

    private var boxWidth: CGFloat { textSize.width + padding * 2 }
    private var boxHeight: CGFloat { textSize.height + padding * 2 }

    // The emoji button height + spacing above the text box
    private let emojiHeight: CGFloat = 26
    private let emojiSpacing: CGFloat = 4

    var body: some View {
        // position = top-left of text content in view space
        // We need to place the VStack so the text content aligns there
        let offsetX = position.x + boxWidth / 2
        let offsetY = position.y - emojiHeight - emojiSpacing + boxHeight / 2

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
                    // Dashed blue rectangle border
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: boxWidth, height: boxHeight)

                    // Multi-line text view
                    MultiLineTextView(
                        text: $text,
                        color: nsColor,
                        fontSize: fontSize,
                        textStyle: textStyle,
                        onCancel: onCancel
                    )
                    .frame(width: textSize.width, height: textSize.height)

                    // Mid-left circle handle
                    handleCircle(xOffset: -(boxWidth / 2), yOffset: 0)
                    // Mid-right circle handle
                    handleCircle(xOffset: (boxWidth / 2), yOffset: 0)
                    // Bottom-right small square handle
                    handleSquare(xOffset: (boxWidth / 2), yOffset: (boxHeight / 2))
                }
            }
            .position(x: offsetX, y: offsetY)
        }
    }

    // MARK: - Scale handles

    private func handleCircle(xOffset: CGFloat, yOffset: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: circleDiameter, height: circleDiameter)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .offset(x: xOffset, y: yOffset)
            .gesture(scaleGesture)
    }

    private func handleSquare(xOffset: CGFloat, yOffset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: squareSize, height: squareSize)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 2))
            .offset(x: xOffset, y: yOffset)
            .gesture(scaleGesture)
    }

    private var scaleGesture: some Gesture {
        DragGesture()
            .updating($scaleStart) { _, state, _ in
                if state == nil { state = fontSize }
            }
            .onChanged { value in
                guard let start = scaleStart else { return }
                let delta = (value.translation.width + value.translation.height) * 0.08
                fontSize = max(start + delta, 10)
            }
    }

}

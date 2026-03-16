//
//  AnnotationCanvasView.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit

final class AnnotationCanvasView: NSView {
    var image: NSImage
    var annotationState: AnnotationState

    // Coordinate mapping
    private var imageRect: CGRect = .zero
    private var imageToViewScale: CGFloat = 1.0

    // Drawing state
    private var isDrawing = false
    private var dragStartImagePoint: CGPoint = .zero

    // Cursor/selection state
    private var isDraggingSelection = false
    private var isResizingSelection = false
    private var resizeHandle: ResizeHandle = .none
    private var lastDragImagePoint: CGPoint = .zero
    private var resizeAnchorPoint: CGPoint = .zero  // Opposite corner stays fixed
    private var resizeStartFontSize: CGFloat = 0    // For text annotation scaling
    private var resizeStartDragPoint: CGPoint = .zero // Initial drag point (for distance ratio)

    private enum ResizeHandle {
        case none, topLeft, topRight, bottomLeft, bottomRight
        case midLeft, midRight   // For text annotations
    }

    // Crop state
    private var cropRect: CGRect?  // In image space, while dragging

    // Text editing — passes (imagePoint, viewPoint, imageToViewScale) for new text
    var onRequestTextEditor: ((CGPoint, CGPoint, CGFloat) -> Void)?

    // Edit existing text annotation — passes (annotationID, currentText, viewPoint, imageToViewScale)
    var onRequestEditTextAnnotation: ((UUID, String, CGPoint, CGFloat) -> Void)?

    // When editing a text annotation, hide it from drawing so the overlay replaces it
    var editingAnnotationID: UUID?

    // Crop callback — sends the cropped image back
    var onImageCropped: ((NSImage) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(image: NSImage, annotationState: AnnotationState) {
        self.image = image
        self.annotationState = annotationState
        super.init(frame: .zero)

        annotationState.onStateChanged = { [weak self] in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        computeImageRect()
    }

    private func computeImageRect() {
        let viewSize = bounds.size
        let imgSize = image.size
        guard viewSize.width > 0, viewSize.height > 0,
              imgSize.width > 0, imgSize.height > 0 else { return }

        let scaleX = viewSize.width / imgSize.width
        let scaleY = viewSize.height / imgSize.height
        let scale = min(scaleX, scaleY)

        let drawWidth = imgSize.width * scale
        let drawHeight = imgSize.height * scale
        let drawX = (viewSize.width - drawWidth) / 2
        let drawY = (viewSize.height - drawHeight) / 2

        imageRect = CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)
        imageToViewScale = scale
    }

    // MARK: - Coordinate Conversion

    private func viewPointToImagePoint(_ viewPoint: CGPoint) -> CGPoint {
        guard imageToViewScale > 0 else { return .zero }
        return CGPoint(
            x: (viewPoint.x - imageRect.origin.x) / imageToViewScale,
            y: (viewPoint.y - imageRect.origin.y) / imageToViewScale
        )
    }

    private func imagePointToViewPoint(_ imagePoint: CGPoint) -> CGPoint {
        return CGPoint(
            x: imagePoint.x * imageToViewScale + imageRect.origin.x,
            y: imagePoint.y * imageToViewScale + imageRect.origin.y
        )
    }

    private func imageRectToViewRect(_ rect: CGRect) -> CGRect {
        let origin = imagePointToViewPoint(rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * imageToViewScale,
            height: rect.height * imageToViewScale
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(bounds)

        computeImageRect()

        // Draw image
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.saveGState()
            ctx.translateBy(x: imageRect.origin.x, y: imageRect.origin.y + imageRect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: imageRect.size))
            ctx.restoreGState()
        }

        // Draw completed annotations (skip the one being edited in-place)
        for annotation in annotationState.annotations {
            if annotation.id == editingAnnotationID { continue }
            drawAnnotation(annotation, in: ctx)
        }

        // Draw active (in-progress) annotation
        if let active = annotationState.activeAnnotation {
            drawAnnotation(active, in: ctx)
        }

        // Draw selection handles for selected annotation (not while editing in-place)
        if let selectedID = annotationState.selectedAnnotationID,
           selectedID != editingAnnotationID,
           let annotation = annotationState.annotations.first(where: { $0.id == selectedID }) {
            drawSelectionHandles(for: annotation, in: ctx)
        }

        // Draw crop overlay
        if let crop = cropRect {
            drawCropOverlay(crop, in: ctx)
        }
    }

    private func drawCropOverlay(_ crop: CGRect, in ctx: CGContext) {
        let viewCrop = imageRectToViewRect(crop)

        // Dim area outside the crop rect
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.addRect(imageRect)
        ctx.addRect(viewCrop)
        ctx.drawPath(using: .eoFill)
        ctx.restoreGState()

        // Crop border
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(viewCrop)

        // Grid lines (rule of thirds)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1...2 {
            let fraction = CGFloat(i) / 3.0
            // Vertical
            let x = viewCrop.minX + viewCrop.width * fraction
            ctx.move(to: CGPoint(x: x, y: viewCrop.minY))
            ctx.addLine(to: CGPoint(x: x, y: viewCrop.maxY))
            // Horizontal
            let y = viewCrop.minY + viewCrop.height * fraction
            ctx.move(to: CGPoint(x: viewCrop.minX, y: y))
            ctx.addLine(to: CGPoint(x: viewCrop.maxX, y: y))
        }
        ctx.strokePath()
    }

    private func drawSelectionHandles(for annotation: Annotation, in ctx: CGContext) {
        let bounds = annotation.hitBounds
        let viewRect = imageRectToViewRect(bounds)
        let handleRadius: CGFloat = 7
        let smallHandleSize: CGFloat = 10

        if annotation.tool == .text {
            // CleanShot X style: dashed rectangle, mid-edge circles, bottom-right square
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            ctx.stroke(viewRect)
            ctx.setLineDash(phase: 0, lengths: [])

            // Circle handles at mid-left and mid-right
            let midHandles = [
                CGPoint(x: viewRect.minX, y: viewRect.midY),
                CGPoint(x: viewRect.maxX, y: viewRect.midY)
            ]
            for pt in midHandles {
                let circleRect = CGRect(
                    x: pt.x - handleRadius,
                    y: pt.y - handleRadius,
                    width: handleRadius * 2,
                    height: handleRadius * 2
                )
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: circleRect)
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: circleRect)
            }

            // Small square handle at bottom-right
            let sqRect = CGRect(
                x: viewRect.maxX - smallHandleSize / 2,
                y: viewRect.maxY - smallHandleSize / 2,
                width: smallHandleSize,
                height: smallHandleSize
            )
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(sqRect)
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(sqRect)
        } else {
            // Other annotations: dashed outline + circle corner handles
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(viewRect)
            ctx.setLineDash(phase: 0, lengths: [])

            let corners = [
                CGPoint(x: viewRect.minX, y: viewRect.minY),
                CGPoint(x: viewRect.maxX, y: viewRect.minY),
                CGPoint(x: viewRect.minX, y: viewRect.maxY),
                CGPoint(x: viewRect.maxX, y: viewRect.maxY)
            ]
            for corner in corners {
                let circleRect = CGRect(
                    x: corner.x - handleRadius,
                    y: corner.y - handleRadius,
                    width: handleRadius * 2,
                    height: handleRadius * 2
                )
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: circleRect)
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: circleRect)
            }
        }
    }

    private func drawAnnotation(_ annotation: Annotation, in ctx: CGContext) {
        switch annotation.tool {
        case .arrow:     drawArrow(annotation, in: ctx)
        case .rectangle: drawRectangle(annotation, in: ctx)
        case .circle:    drawCircle(annotation, in: ctx)
        case .line:      drawLine(annotation, in: ctx)
        case .pen:       drawFreehand(annotation, in: ctx)
        case .text:      drawText(annotation, in: ctx)
        default:         break
        }
    }

    // MARK: - Shape Drawing

    private func drawArrow(_ annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count >= 2 else { return }
        let p1 = imagePointToViewPoint(annotation.points[0])
        let p2 = imagePointToViewPoint(annotation.points[1])
        let lw = annotation.lineWidth * imageToViewScale

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)

        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()

        // Arrowhead
        let angle = atan2(p2.y - p1.y, p2.x - p1.x)
        let headLength = max(12, lw * 5)
        let headAngle: CGFloat = .pi / 6

        let left = CGPoint(
            x: p2.x - headLength * cos(angle - headAngle),
            y: p2.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: p2.x - headLength * cos(angle + headAngle),
            y: p2.y - headLength * sin(angle + headAngle)
        )

        ctx.setFillColor(annotation.color.cgColor)
        ctx.move(to: p2)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    private func drawRectangle(_ annotation: Annotation, in ctx: CGContext) {
        let viewRect = imageRectToViewRect(annotation.boundingRect)
        let lw = annotation.lineWidth * imageToViewScale

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(lw)
        ctx.stroke(viewRect)
    }

    private func drawCircle(_ annotation: Annotation, in ctx: CGContext) {
        let viewRect = imageRectToViewRect(annotation.boundingRect)
        let lw = annotation.lineWidth * imageToViewScale

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(lw)
        ctx.strokeEllipse(in: viewRect)
    }

    private func drawLine(_ annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count >= 2 else { return }
        let p1 = imagePointToViewPoint(annotation.points[0])
        let p2 = imagePointToViewPoint(annotation.points[1])
        let lw = annotation.lineWidth * imageToViewScale

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()
    }

    private func drawFreehand(_ annotation: Annotation, in ctx: CGContext) {
        let viewPoints = annotation.points.map { imagePointToViewPoint($0) }
        guard viewPoints.count >= 2 else { return }
        let lw = annotation.lineWidth * imageToViewScale

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.move(to: viewPoints[0])
        if viewPoints.count == 2 {
            ctx.addLine(to: viewPoints[1])
        } else {
            for i in 1..<viewPoints.count - 1 {
                let mid = CGPoint(
                    x: (viewPoints[i].x + viewPoints[i + 1].x) / 2,
                    y: (viewPoints[i].y + viewPoints[i + 1].y) / 2
                )
                ctx.addQuadCurve(to: mid, control: viewPoints[i])
            }
            ctx.addLine(to: viewPoints.last!)
        }
        ctx.strokePath()
    }

    private func drawText(_ annotation: Annotation, in ctx: CGContext) {
        guard !annotation.text.isEmpty else { return }
        let viewPoint = imagePointToViewPoint(annotation.boundingRect.origin)
        let viewFontSize = annotation.fontSize * imageToViewScale
        let font = annotation.textStyle.font(ofSize: viewFontSize)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.color
        ]
        let attrStr = NSAttributedString(string: annotation.text, attributes: attrs)
        let textBounds = attrStr.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = CGRect(origin: viewPoint, size: textBounds.size)

        // Draw background box if style requires it
        if annotation.textStyle.hasBackground {
            let bgPadding: CGFloat = 4 * imageToViewScale
            let bgRect = drawRect.insetBy(dx: -bgPadding, dy: -bgPadding)
            ctx.setFillColor(annotation.color.withAlphaComponent(0.2).cgColor)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4 * imageToViewScale, cornerHeight: 4 * imageToViewScale, transform: nil)
            ctx.addPath(bgPath)
            ctx.fillPath()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        if annotation.textStyle.isOutlined {
            // Outlined: stroke text
            let strokeAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: annotation.color,
                .strokeColor: annotation.color,
                .strokeWidth: -3.0
            ]
            let strokeStr = NSAttributedString(string: annotation.text, attributes: strokeAttrs)
            strokeStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        } else {
            attrStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewPointToImagePoint(viewPoint)

        // Double-click on text → edit in-place (any tool)
        if event.clickCount == 2 {
            for annotation in annotationState.annotations.reversed() {
                if annotation.tool == .text && annotation.hitBounds.contains(imagePoint) {
                    let vp = imagePointToViewPoint(annotation.boundingRect.origin)
                    onRequestEditTextAnnotation?(annotation.id, annotation.text, vp, imageToViewScale)
                    return
                }
            }
        }

        // Cursor tool: single-click → select / move / resize
        if annotationState.selectedTool == .cursor {
            handleCursorMouseDown(viewPoint: viewPoint, imagePoint: imagePoint)
            return
        }

        // Text tool: allow resize handles on selected text annotation
        if annotationState.selectedTool == .text,
           let selectedID = annotationState.selectedAnnotationID,
           let annotation = annotationState.annotations.first(where: { $0.id == selectedID }),
           annotation.tool == .text {
            let handle = hitTestResizeHandle(viewPoint: viewPoint, annotation: annotation)
            if handle != .none {
                isResizingSelection = true
                resizeHandle = handle
                lastDragImagePoint = imagePoint
                resizeStartDragPoint = imagePoint
                resizeStartFontSize = annotation.fontSize
                let b = annotation.hitBounds
                switch handle {
                case .topLeft:     resizeAnchorPoint = CGPoint(x: b.maxX, y: b.maxY)
                case .topRight:    resizeAnchorPoint = CGPoint(x: b.minX, y: b.maxY)
                case .bottomLeft:  resizeAnchorPoint = CGPoint(x: b.maxX, y: b.minY)
                case .bottomRight: resizeAnchorPoint = CGPoint(x: b.minX, y: b.minY)
                case .midLeft:     resizeAnchorPoint = CGPoint(x: b.maxX, y: b.midY)
                case .midRight:    resizeAnchorPoint = CGPoint(x: b.minX, y: b.midY)
                case .none: break
                }
                return
            }
        }

        // Other tools: allow dragging existing annotations
        if startDraggingAnnotationIfHit(imagePoint: imagePoint) {
            return
        }

        guard annotationState.selectedTool.isDrawingTool else { return }
        guard imageRect.contains(viewPoint) else { return }

        // Deselect when drawing
        annotationState.selectedAnnotationID = nil

        if annotationState.selectedTool == .crop {
            isDrawing = true
            NSCursor.crosshair.set()
            dragStartImagePoint = imagePoint
            cropRect = CGRect(origin: imagePoint, size: .zero)
            return
        }

        // Text tool: click on existing text → drag it; click empty → new text
        if annotationState.selectedTool == .text {
            for annotation in annotationState.annotations.reversed() {
                if annotation.tool == .text && annotation.hitBounds.contains(imagePoint) {
                    annotationState.selectedAnnotationID = annotation.id
                    isDraggingSelection = true
                    lastDragImagePoint = imagePoint
                    NSCursor.closedHand.set()
                    needsDisplay = true
                    return
                }
            }
            onRequestTextEditor?(imagePoint, viewPoint, imageToViewScale)
            return
        }

        isDrawing = true
        NSCursor.crosshair.set()
        dragStartImagePoint = imagePoint

        var annotation = Annotation(
            tool: annotationState.selectedTool,
            color: annotationState.selectedColor,
            lineWidth: annotationState.lineWidth
        )

        switch annotationState.selectedTool {
        case .arrow, .line:
            annotation.points = [imagePoint, imagePoint]
        case .rectangle, .circle:
            annotation.boundingRect = CGRect(origin: imagePoint, size: .zero)
        case .pen:
            annotation.points = [imagePoint]
        default:
            break
        }

        annotationState.beginAnnotation(annotation)
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewPointToImagePoint(viewPoint)

        // Dragging/resizing a selected annotation
        if isDraggingSelection || isResizingSelection {
            handleCursorMouseDragged(imagePoint: imagePoint)
            return
        }

        // Crop dragging
        if annotationState.selectedTool == .crop && isDrawing {
            let x = min(dragStartImagePoint.x, imagePoint.x)
            let y = min(dragStartImagePoint.y, imagePoint.y)
            let w = abs(imagePoint.x - dragStartImagePoint.x)
            let h = abs(imagePoint.y - dragStartImagePoint.y)
            cropRect = CGRect(x: x, y: y, width: w, height: h)
            needsDisplay = true
            return
        }

        guard isDrawing, var annotation = annotationState.activeAnnotation else { return }

        switch annotation.tool {
        case .arrow, .line:
            if annotation.points.count >= 2 {
                annotation.points[1] = imagePoint
            }
        case .rectangle, .circle:
            let x = min(dragStartImagePoint.x, imagePoint.x)
            let y = min(dragStartImagePoint.y, imagePoint.y)
            let w = abs(imagePoint.x - dragStartImagePoint.x)
            let h = abs(imagePoint.y - dragStartImagePoint.y)
            annotation.boundingRect = CGRect(x: x, y: y, width: w, height: h)
        case .pen:
            annotation.points.append(imagePoint)
        default:
            break
        }

        annotationState.updateActiveAnnotation(annotation)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = isDraggingSelection || isResizingSelection
        if wasDragging {
            isDraggingSelection = false
            isResizingSelection = false
            resizeHandle = .none
            // Restore cursor based on current position
            let viewPoint = convert(event.locationInWindow, from: nil)
            let imagePoint = viewPointToImagePoint(viewPoint)
            updateCursorForPoint(viewPoint: viewPoint, imagePoint: imagePoint)
            return
        }

        guard isDrawing else { return }
        isDrawing = false

        // Apply crop
        if annotationState.selectedTool == .crop, let crop = cropRect {
            applyCrop(crop)
            cropRect = nil
            return
        }

        annotationState.commitActiveAnnotation()
    }

    // MARK: - Crop

    private func applyCrop(_ cropImageRect: CGRect) {
        guard cropImageRect.width > 2, cropImageRect.height > 2 else { return }

        // First render annotations onto current image
        let annotatedImage = AnnotationRenderer.render(annotations: annotationState.annotations, onto: image)

        guard let cgImage = annotatedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        // Convert from image-space (top-left origin) to CGImage space (bottom-left origin)
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let scaleX = imgW / image.size.width
        let scaleY = imgH / image.size.height

        let pixelRect = CGRect(
            x: cropImageRect.origin.x * scaleX,
            y: cropImageRect.origin.y * scaleY,
            width: cropImageRect.width * scaleX,
            height: cropImageRect.height * scaleY
        )

        // Clamp to image bounds
        let clampedRect = pixelRect.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard clampedRect.width > 0, clampedRect.height > 0 else { return }

        guard let croppedCG = cgImage.cropping(to: clampedRect) else { return }

        let croppedImage = NSImage(cgImage: croppedCG, size: NSSize(width: clampedRect.width / scaleX, height: clampedRect.height / scaleY))

        // Clear annotations (they're baked into the cropped image)
        annotationState.clearAll()

        // Update the image
        image = croppedImage
        computeImageRect()
        needsDisplay = true

        // Notify parent
        onImageCropped?(croppedImage)
    }

    // MARK: - Cursor Tool Handling

    private func handleCursorMouseDown(viewPoint: CGPoint, imagePoint: CGPoint) {
        // Check if clicking on a resize handle of the selected annotation
        if let selectedID = annotationState.selectedAnnotationID,
           let annotation = annotationState.annotations.first(where: { $0.id == selectedID }) {
            let handle = hitTestResizeHandle(viewPoint: viewPoint, annotation: annotation)
            if handle != .none {
                isResizingSelection = true
                resizeHandle = handle
                lastDragImagePoint = imagePoint
                resizeStartDragPoint = imagePoint
                resizeStartFontSize = annotation.fontSize
                // Anchor is the opposite corner/edge
                let b = annotation.hitBounds
                switch handle {
                case .topLeft:     resizeAnchorPoint = CGPoint(x: b.maxX, y: b.maxY)
                case .topRight:    resizeAnchorPoint = CGPoint(x: b.minX, y: b.maxY)
                case .bottomLeft:  resizeAnchorPoint = CGPoint(x: b.maxX, y: b.minY)
                case .bottomRight: resizeAnchorPoint = CGPoint(x: b.minX, y: b.minY)
                case .midLeft:     resizeAnchorPoint = CGPoint(x: b.maxX, y: b.midY)
                case .midRight:    resizeAnchorPoint = CGPoint(x: b.minX, y: b.midY)
                case .none: break
                }
                return
            }
        }

        // Check if clicking on any annotation to select it
        // Search in reverse order (top-most first)
        for annotation in annotationState.annotations.reversed() {
            if annotation.hitBounds.contains(imagePoint) {
                annotationState.selectedAnnotationID = annotation.id
                isDraggingSelection = true
                lastDragImagePoint = imagePoint
                NSCursor.closedHand.set()
                needsDisplay = true
                return
            }
        }

        // Clicked empty space — deselect
        annotationState.selectedAnnotationID = nil
        isDraggingSelection = false
        needsDisplay = true
    }

    private func handleCursorMouseDragged(imagePoint: CGPoint) {
        guard let selectedID = annotationState.selectedAnnotationID,
              let idx = annotationState.annotations.firstIndex(where: { $0.id == selectedID }) else { return }

        if isResizingSelection {
            if annotationState.annotations[idx].tool == .text {
                // Text: scale font size based on drag distance from anchor
                // Use resizeStartDragPoint (fixed) not lastDragImagePoint (changes)
                let startDist = hypot(
                    resizeStartDragPoint.x - resizeAnchorPoint.x,
                    resizeStartDragPoint.y - resizeAnchorPoint.y
                )
                let currentDist = hypot(
                    imagePoint.x - resizeAnchorPoint.x,
                    imagePoint.y - resizeAnchorPoint.y
                )
                guard startDist > 1 else { return }
                let scaleFactor = currentDist / startDist
                annotationState.annotations[idx].fontSize = max(resizeStartFontSize * scaleFactor, 8)
                annotationState.onStateChanged?()
            } else {
                // Freeform resize: dragged corner moves to mouse, opposite corner stays anchored
                let anchor = resizeAnchorPoint
                let newRect = CGRect(
                    x: min(anchor.x, imagePoint.x),
                    y: min(anchor.y, imagePoint.y),
                    width: abs(imagePoint.x - anchor.x),
                    height: abs(imagePoint.y - anchor.y)
                )
                annotationState.annotations[idx].resizeToRect(newRect)
                lastDragImagePoint = imagePoint
                annotationState.onStateChanged?()
            }
        } else if isDraggingSelection {
            // Move
            let dx = imagePoint.x - lastDragImagePoint.x
            let dy = imagePoint.y - lastDragImagePoint.y
            annotationState.annotations[idx].translate(dx: dx, dy: dy)
            lastDragImagePoint = imagePoint
            annotationState.onStateChanged?()
        }
    }

    private func hitTestResizeHandle(viewPoint: CGPoint, annotation: Annotation) -> ResizeHandle {
        let bounds = annotation.hitBounds
        let viewRect = imageRectToViewRect(bounds)
        let handleSize: CGFloat = 18

        let handles: [(CGPoint, ResizeHandle)]

        if annotation.tool == .text {
            // Text: mid-left, mid-right circles + bottom-right square
            handles = [
                (CGPoint(x: viewRect.minX, y: viewRect.midY), .midLeft),
                (CGPoint(x: viewRect.maxX, y: viewRect.midY), .midRight),
                (CGPoint(x: viewRect.maxX, y: viewRect.maxY), .bottomRight)
            ]
        } else {
            // Other: 4 corner handles
            handles = [
                (CGPoint(x: viewRect.minX, y: viewRect.minY), .topLeft),
                (CGPoint(x: viewRect.maxX, y: viewRect.minY), .topRight),
                (CGPoint(x: viewRect.minX, y: viewRect.maxY), .bottomLeft),
                (CGPoint(x: viewRect.maxX, y: viewRect.maxY), .bottomRight)
            ]
        }

        for (corner, handle) in handles {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            if handleRect.contains(viewPoint) {
                return handle
            }
        }
        return .none
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            annotationState.undoLast()
        } else if event.keyCode == 51 || event.keyCode == 117 { // Delete or Forward Delete
            deleteSelectedAnnotation()
        } else {
            super.keyDown(with: event)
        }
    }

    private func deleteSelectedAnnotation() {
        guard let selectedID = annotationState.selectedAnnotationID else { return }
        annotationState.annotations.removeAll { $0.id == selectedID }
        annotationState.selectedAnnotationID = nil
        annotationState.onStateChanged?()
    }

    // MARK: - Mouse Tracking & Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewPointToImagePoint(viewPoint)

        updateCursorForPoint(viewPoint: viewPoint, imagePoint: imagePoint)
    }

    private func updateCursorForPoint(viewPoint: CGPoint, imagePoint: CGPoint) {
        // Check if hovering over a resize handle of selected annotation (cursor or text tool)
        if (annotationState.selectedTool == .cursor || annotationState.selectedTool == .text),
           let selectedID = annotationState.selectedAnnotationID,
           let annotation = annotationState.annotations.first(where: { $0.id == selectedID }) {
            let handle = hitTestResizeHandle(viewPoint: viewPoint, annotation: annotation)
            if handle != .none {
                // Resize cursor based on handle position
                switch handle {
                case .topLeft, .bottomRight:
                    NSCursor.crosshair.set()
                case .topRight, .bottomLeft:
                    NSCursor.crosshair.set()
                case .midLeft, .midRight:
                    NSCursor.resizeLeftRight.set()
                case .none:
                    break
                }
                return
            }
        }

        // Check if hovering over any annotation
        for annotation in annotationState.annotations.reversed() {
            if annotation.hitBounds.contains(imagePoint) {
                NSCursor.openHand.set()
                return
            }
        }
        if isDrawing {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func startDraggingAnnotationIfHit(imagePoint: CGPoint) -> Bool {
        for annotation in annotationState.annotations.reversed() {
            if annotation.hitBounds.contains(imagePoint) {
                annotationState.selectedAnnotationID = annotation.id
                isDraggingSelection = true
                lastDragImagePoint = imagePoint
                NSCursor.closedHand.set()
                needsDisplay = true
                return true
            }
        }
        return false
    }

    override func resetCursorRects() {
        // Handled dynamically via mouseMoved
    }
}

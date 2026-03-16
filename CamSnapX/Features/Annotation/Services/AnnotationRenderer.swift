//
//  AnnotationRenderer.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit

/// Renders annotations onto an NSImage using CGContext (image-space coordinates)
final class AnnotationRenderer {

    /// Returns a new NSImage with all annotations baked in
    static func render(annotations: [Annotation], onto image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Draw original image (CGContext y=0 is bottom)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Map annotation coordinates (image.size points) into pixel space,
        // then flip to top-left origin for annotation drawing.
        let scaleX = CGFloat(width) / max(image.size.width, 1)
        let scaleY = CGFloat(height) / max(image.size.height, 1)
        ctx.saveGState()
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.translateBy(x: 0, y: image.size.height)
        ctx.scaleBy(x: 1, y: -1)

        // Draw each annotation in image space
        for annotation in annotations {
            drawAnnotation(annotation, in: ctx)
        }

        ctx.restoreGState()

        guard let result = ctx.makeImage() else { return image }
        return NSImage(cgImage: result, size: image.size)
    }

    // MARK: - Individual Drawing

    private static func drawAnnotation(_ annotation: Annotation, in ctx: CGContext) {
        switch annotation.tool {
        case .arrow:     drawArrow(annotation, in: ctx)
        case .rectangle: drawRectangle(annotation, in: ctx)
        case .filledRectangle: drawFilledRectangle(annotation, in: ctx)
        case .circle:    drawCircle(annotation, in: ctx)
        case .line:      drawLine(annotation, in: ctx)
        case .pen:       drawFreehand(annotation, in: ctx)
        case .text:      drawText(annotation, in: ctx)
        default:         break
        }
    }

    private static func drawArrow(_ annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count >= 2 else { return }
        let p1 = annotation.points[0]
        let p2 = annotation.points[1]

        switch annotation.arrowStyle {
        case .standard:
            drawArrowLine(from: p1, to: p2, color: annotation.color, lineWidth: annotation.lineWidth, in: ctx)
            drawArrowHead(at: p2, from: p1, color: annotation.color, lineWidth: annotation.lineWidth, filled: false, in: ctx)
        case .fancy:
            drawFancyArrow(from: p1, to: p2, color: annotation.color, lineWidth: annotation.lineWidth, in: ctx)
        case .curved:
            let control = annotation.curveControlPoint ?? curvedControlPoint(from: p1, to: p2)
            drawCurvedArrowLine(from: p1, to: p2, control: control, color: annotation.color, lineWidth: annotation.lineWidth, in: ctx)
            drawArrowHead(at: p2, from: control, color: annotation.color, lineWidth: annotation.lineWidth, filled: false, in: ctx)
        case .double:
            let control = annotation.curveControlPoint ?? CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            drawCurvedArrowLine(from: p1, to: p2, control: control, color: annotation.color, lineWidth: annotation.lineWidth, in: ctx)
            drawArrowHead(at: p2, from: control, color: annotation.color, lineWidth: annotation.lineWidth, filled: false, in: ctx)
            drawArrowHead(at: p1, from: control, color: annotation.color, lineWidth: annotation.lineWidth, filled: false, in: ctx)
        }
    }

    private static func drawArrowLine(from p1: CGPoint, to p2: CGPoint, color: NSColor, lineWidth: CGFloat, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()
    }

    private static func drawFancyArrow(from p1: CGPoint, to p2: CGPoint, color: NSColor, lineWidth: CGFloat, in ctx: CGContext) {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let distance = max(hypot(dx, dy), 1)
        let ux = dx / distance
        let uy = dy / distance
        let px = -uy
        let py = ux

        let shaftWidth = max(2, lineWidth * 0.55)
        let headWidth = max(14, lineWidth * 5.0)
        let headLength = max(24, lineWidth * 9)
        let shaftLength = max(distance - headLength, distance * 0.6)
        let shaftEnd = CGPoint(x: p1.x + ux * shaftLength, y: p1.y + uy * shaftLength)
        let headBase = CGPoint(x: p2.x - ux * headLength, y: p2.y - uy * headLength)

        let tailLeft = CGPoint(x: p1.x + px * shaftWidth, y: p1.y + py * shaftWidth)
        let tailRight = CGPoint(x: p1.x - px * shaftWidth, y: p1.y - py * shaftWidth)
        let shaftLeft = CGPoint(x: shaftEnd.x + px * shaftWidth, y: shaftEnd.y + py * shaftWidth)
        let shaftRight = CGPoint(x: shaftEnd.x - px * shaftWidth, y: shaftEnd.y - py * shaftWidth)
        let headLeft = CGPoint(x: headBase.x + px * headWidth, y: headBase.y + py * headWidth)
        let headRight = CGPoint(x: headBase.x - px * headWidth, y: headBase.y - py * headWidth)

        ctx.setFillColor(color.cgColor)
        ctx.beginPath()
        ctx.move(to: tailLeft)
        ctx.addLine(to: shaftLeft)
        ctx.addLine(to: headLeft)
        ctx.addLine(to: p2)
        ctx.addLine(to: headRight)
        ctx.addLine(to: shaftRight)
        ctx.addLine(to: tailRight)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawCurvedArrowLine(from p1: CGPoint, to p2: CGPoint, control: CGPoint, color: NSColor, lineWidth: CGFloat, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: p1)
        ctx.addQuadCurve(to: p2, control: control)
        ctx.strokePath()
    }

    private static func curvedControlPoint(from p1: CGPoint, to p2: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let distance = max(hypot(dx, dy), 1)
        let offset = min(40, max(14, distance * 0.2))
        let perp = CGPoint(x: -dy / distance * offset, y: dx / distance * offset)
        return CGPoint(x: mid.x + perp.x, y: mid.y + perp.y)
    }


    private static func drawArrowHead(at tip: CGPoint, from tail: CGPoint, color: NSColor, lineWidth: CGFloat, filled: Bool, headLength: CGFloat? = nil, headAngle: CGFloat = .pi / 6, in ctx: CGContext) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let resolvedLength = headLength ?? max(12, lineWidth * 5)

        let left = CGPoint(
            x: tip.x - resolvedLength * cos(angle - headAngle),
            y: tip.y - resolvedLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: tip.x - resolvedLength * cos(angle + headAngle),
            y: tip.y - resolvedLength * sin(angle + headAngle)
        )

        if filled {
            ctx.setFillColor(color.cgColor)
            ctx.move(to: tip)
            ctx.addLine(to: left)
            ctx.addLine(to: right)
            ctx.closePath()
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.move(to: left)
            ctx.addLine(to: tip)
            ctx.addLine(to: right)
            ctx.strokePath()
        }
    }

    private static func drawRectangle(_ annotation: Annotation, in ctx: CGContext) {
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.stroke(annotation.boundingRect)
    }

    private static func drawFilledRectangle(_ annotation: Annotation, in ctx: CGContext) {
        ctx.setFillColor(annotation.color.cgColor)
        ctx.fill(annotation.boundingRect)
    }

    private static func drawCircle(_ annotation: Annotation, in ctx: CGContext) {
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.strokeEllipse(in: annotation.boundingRect)
    }

    private static func drawLine(_ annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count >= 2 else { return }

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: annotation.points[0])
        ctx.addLine(to: annotation.points[1])
        ctx.strokePath()
    }

    private static func drawFreehand(_ annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count >= 2 else { return }

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.move(to: annotation.points[0])
        if annotation.points.count == 2 {
            ctx.addLine(to: annotation.points[1])
        } else {
            for i in 1..<annotation.points.count - 1 {
                let mid = CGPoint(
                    x: (annotation.points[i].x + annotation.points[i + 1].x) / 2,
                    y: (annotation.points[i].y + annotation.points[i + 1].y) / 2
                )
                ctx.addQuadCurve(to: mid, control: annotation.points[i])
            }
            ctx.addLine(to: annotation.points.last!)
        }
        ctx.strokePath()
    }

    private static func drawText(_ annotation: Annotation, in ctx: CGContext) {
        guard !annotation.text.isEmpty else { return }
        let font = annotation.textStyle.font(ofSize: annotation.fontSize)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.color
        ]
        let attrStr = NSAttributedString(string: annotation.text, attributes: attrs)
        let textMaxWidth = max((annotation.textBoxWidth ?? 0) - 8, 1)
        let constraintWidth = annotation.textBoxWidth == nil ? CGFloat.greatestFiniteMagnitude : textMaxWidth
        let textBounds = attrStr.boundingRect(
            with: CGSize(width: constraintWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let minW: CGFloat = 40
        let minH: CGFloat = 20
        let baseW = max(ceil(textBounds.width) + 8, minW)
        let baseH = max(ceil(textBounds.height) + 8, minH)
        let boxW = max(baseW, annotation.textBoxWidth ?? 0)
        let boxRect = CGRect(origin: annotation.boundingRect.origin, size: CGSize(width: boxW, height: baseH))
        let drawRect = boxRect.insetBy(dx: 4, dy: 4)

        // Draw tight background behind text (white, with style-specific corner radius)
        if annotation.textStyle.hasBackground {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            let bgPadH: CGFloat = 8
            let bgPadV: CGFloat = 4
            let textW = ceil(textBounds.width)
            let textH = ceil(textBounds.height)
            let bgW = textW + bgPadH * 2
            let bgH = textH + bgPadV * 2
            let bgX = annotation.boundingRect.origin.x + 4 - bgPadH
            let bgY = annotation.boundingRect.origin.y + 4 - bgPadV
            let bgRect = CGRect(x: bgX, y: bgY, width: bgW, height: bgH)
            let cornerRadius = annotation.textStyle.backgroundCornerRadius
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(bgPath)
            ctx.fillPath()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        if annotation.textStyle.isOutlined {
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
}

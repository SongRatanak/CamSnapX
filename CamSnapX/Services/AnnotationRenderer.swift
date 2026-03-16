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

        // Flip for annotation drawing (annotations use top-left origin)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Draw each annotation in image space
        for annotation in annotations {
            drawAnnotation(annotation, in: ctx)
        }

        guard let result = ctx.makeImage() else { return image }
        return NSImage(cgImage: result, size: image.size)
    }

    // MARK: - Individual Drawing

    private static func drawAnnotation(_ annotation: Annotation, in ctx: CGContext) {
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

    private static func drawArrow(_ annotation: Annotation, in ctx: CGContext) {
        guard annotation.points.count >= 2 else { return }
        let p1 = annotation.points[0]
        let p2 = annotation.points[1]

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.setLineCap(.round)

        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()

        // Arrowhead
        let angle = atan2(p2.y - p1.y, p2.x - p1.x)
        let headLength = max(12, annotation.lineWidth * 5)
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

    private static func drawRectangle(_ annotation: Annotation, in ctx: CGContext) {
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.stroke(annotation.boundingRect)
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
        let textBounds = attrStr.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = CGRect(origin: annotation.boundingRect.origin, size: textBounds.size)

        // Draw background box if style requires it
        if annotation.textStyle.hasBackground {
            let bgPadding: CGFloat = 4
            let bgRect = drawRect.insetBy(dx: -bgPadding, dy: -bgPadding)
            ctx.setFillColor(annotation.color.withAlphaComponent(0.2).cgColor)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
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

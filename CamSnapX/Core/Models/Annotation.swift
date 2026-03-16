//
//  Annotation.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit

/// Tool types available in the annotation toolbar
enum AnnotationTool: String, CaseIterable {
    // Group 1: File operations (placeholder)
    case crop, copyArea, addImage
    // Group 2: Drawing tools (functional)
    case cursor, rectangle, filledRectangle, circle, line, arrow, text
    // Group 3: Effects (placeholder)
    case blur, highlight
    // Group 4: Advanced
    case numberedMarker, pen, eraser, smartAnnotate

    var isDrawingTool: Bool {
        switch self {
        case .crop, .rectangle, .filledRectangle, .circle, .line, .arrow, .text, .pen:
            return true
        default:
            return false
        }
    }
}

/// Arrow style options for arrow annotations
enum ArrowAnnotationStyle: String, CaseIterable {
    case standard = "Standard"
    case fancy = "Fancy"
    case curved = "Curved"
    case double = "Double"
}

/// Text style options for text annotations
enum TextAnnotationStyle: String, CaseIterable {
    case standard     = "Standard"
    case rounded      = "Rounded"
    case outlined     = "Outlined"
    case mono         = "Mono"
    case box          = "Box"
    case monoBox      = "Mono Box"
    case roundedBox   = "Rounded Box"

    /// Returns the NSFont for this style at the given size
    func font(ofSize size: CGFloat) -> NSFont {
        switch self {
        case .standard:
            return .systemFont(ofSize: size, weight: .bold)
        case .rounded:
            let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body).withDesign(.rounded)
            let baseFont = NSFont(descriptor: descriptor ?? NSFontDescriptor(), size: size) ?? .systemFont(ofSize: size)
            return baseFont.withWeight(.bold)
        case .outlined:
            return .systemFont(ofSize: size, weight: .heavy)
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .box:
            return .systemFont(ofSize: size, weight: .bold)
        case .monoBox:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .roundedBox:
            let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body).withDesign(.rounded)
            let baseFont = NSFont(descriptor: descriptor ?? NSFontDescriptor(), size: size) ?? .systemFont(ofSize: size)
            return baseFont.withWeight(.bold)
        }
    }

    /// Whether this style draws a background box behind the text
    var hasBackground: Bool {
        switch self {
        case .box, .monoBox, .roundedBox: return true
        default: return false
        }
    }

    /// Whether this style draws an outline stroke around the text
    var isOutlined: Bool {
        self == .outlined
    }

    /// Corner radius for background: Box/Mono Box = sharp, Rounded Box = rounded
    var backgroundCornerRadius: CGFloat {
        switch self {
        case .monoBox: return 0
        case .box: return 4
        case .roundedBox: return 8
        default: return 0
        }
    }
}

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

/// A single annotation object stored as vector data in image-space coordinates
struct Annotation: Identifiable {
    let id: UUID
    var tool: AnnotationTool
    var color: NSColor
    var lineWidth: CGFloat
    var arrowStyle: ArrowAnnotationStyle
    var curveControlPoint: CGPoint?
    var points: [CGPoint]       // For line, arrow (2 points), pen (many points)
    var boundingRect: CGRect    // For rectangle, circle; origin for text
    var text: String            // For text annotations
    var fontSize: CGFloat       // For text annotations
    var textStyle: TextAnnotationStyle  // For text annotations
    var textBoxWidth: CGFloat?  // Optional override for text box width (image-space)
    var isComplete: Bool

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        color: NSColor = .systemRed,
        lineWidth: CGFloat = 3.0,
        arrowStyle: ArrowAnnotationStyle = .standard,
        curveControlPoint: CGPoint? = nil,
        points: [CGPoint] = [],
        boundingRect: CGRect = .zero,
        text: String = "",
        fontSize: CGFloat = 20.0,
        textStyle: TextAnnotationStyle = .standard,
        textBoxWidth: CGFloat? = nil
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.lineWidth = lineWidth
        self.arrowStyle = arrowStyle
        self.curveControlPoint = curveControlPoint
        self.points = points
        self.boundingRect = boundingRect
        self.text = text
        self.fontSize = fontSize
        self.textStyle = textStyle
        self.textBoxWidth = textBoxWidth
        self.isComplete = false
    }

    /// Returns the bounding box of this annotation in image space
    var hitBounds: CGRect {
        let margin: CGFloat = 6
        switch tool {
        case .rectangle, .filledRectangle, .circle:
            return boundingRect.insetBy(dx: -margin, dy: -margin)
        case .arrow, .line:
            guard points.count >= 2 else { return .zero }
            let minX = min(points[0].x, points[1].x)
            let minY = min(points[0].y, points[1].y)
            let maxX = max(points[0].x, points[1].x)
            let maxY = max(points[0].y, points[1].y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -margin, dy: -margin)
        case .pen:
            guard !points.isEmpty else { return .zero }
            var minX = CGFloat.infinity, minY = CGFloat.infinity
            var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for p in points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -margin, dy: -margin)
        case .text:
            let font = textStyle.font(ofSize: fontSize)
            let displayText = text.isEmpty ? "Text" : text
            let maxWidth = max((textBoxWidth ?? CGFloat.greatestFiniteMagnitude) - 8, 1)
            let measured = (displayText as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            let baseW = max(ceil(measured.width) + 8, 40)
            let baseH = max(ceil(measured.height) + 8, 20)
            let boxW = max(baseW, textBoxWidth ?? 0)
            return CGRect(origin: boundingRect.origin, size: CGSize(width: boxW, height: baseH))
                .insetBy(dx: -margin, dy: -margin)
        default:
            return .zero
        }
    }

    /// Move the annotation by a delta in image space
    mutating func translate(dx: CGFloat, dy: CGFloat) {
        switch tool {
        case .rectangle, .filledRectangle, .circle:
            boundingRect.origin.x += dx
            boundingRect.origin.y += dy
        case .arrow, .line:
            for i in points.indices {
                points[i].x += dx
                points[i].y += dy
            }
            if let control = curveControlPoint {
                curveControlPoint = CGPoint(x: control.x + dx, y: control.y + dy)
            }
        case .pen:
            for i in points.indices {
                points[i].x += dx
                points[i].y += dy
            }
        case .text:
            boundingRect.origin.x += dx
            boundingRect.origin.y += dy
        default:
            break
        }
    }

    /// Scale the annotation around its center by a factor
    mutating func scale(factor: CGFloat) {
        let center = hitBounds.origin.applying(
            CGAffineTransform(translationX: hitBounds.width / 2, y: hitBounds.height / 2)
        )
        switch tool {
        case .rectangle, .filledRectangle, .circle:
            let newW = boundingRect.width * factor
            let newH = boundingRect.height * factor
            boundingRect = CGRect(
                x: center.x - newW / 2,
                y: center.y - newH / 2,
                width: newW,
                height: newH
            )
        case .arrow, .line:
            for i in points.indices {
                points[i].x = center.x + (points[i].x - center.x) * factor
                points[i].y = center.y + (points[i].y - center.y) * factor
            }
            if let control = curveControlPoint {
                curveControlPoint = CGPoint(
                    x: center.x + (control.x - center.x) * factor,
                    y: center.y + (control.y - center.y) * factor
                )
            }
        case .pen:
            for i in points.indices {
                points[i].x = center.x + (points[i].x - center.x) * factor
                points[i].y = center.y + (points[i].y - center.y) * factor
            }
        case .text:
            fontSize *= factor
        default:
            break
        }
    }

    /// Resize the annotation to fit within the given rect (freeform, non-uniform)
    mutating func resizeToRect(_ newRect: CGRect) {
        let oldBounds = hitBounds
        guard oldBounds.width > 1, oldBounds.height > 1,
              newRect.width > 1, newRect.height > 1 else { return }

        let scaleX = newRect.width / oldBounds.width
        let scaleY = newRect.height / oldBounds.height

        switch tool {
        case .rectangle, .filledRectangle, .circle:
            boundingRect = newRect
        case .arrow, .line:
            for i in points.indices {
                let relX = (points[i].x - oldBounds.minX) / oldBounds.width
                let relY = (points[i].y - oldBounds.minY) / oldBounds.height
                points[i].x = newRect.minX + relX * newRect.width
                points[i].y = newRect.minY + relY * newRect.height
            }
            if let control = curveControlPoint {
                let relX = (control.x - oldBounds.minX) / oldBounds.width
                let relY = (control.y - oldBounds.minY) / oldBounds.height
                curveControlPoint = CGPoint(
                    x: newRect.minX + relX * newRect.width,
                    y: newRect.minY + relY * newRect.height
                )
            }
        case .pen:
            for i in points.indices {
                let relX = (points[i].x - oldBounds.minX) / oldBounds.width
                let relY = (points[i].y - oldBounds.minY) / oldBounds.height
                points[i].x = newRect.minX + relX * newRect.width
                points[i].y = newRect.minY + relY * newRect.height
            }
        case .text:
            boundingRect.origin = newRect.origin
            let avgScale = (scaleX + scaleY) / 2
            fontSize *= avgScale
        default:
            break
        }
    }
}

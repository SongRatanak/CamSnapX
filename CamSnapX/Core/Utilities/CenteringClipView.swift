//
//  CenteringClipView.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        guard let documentView else {
            return super.constrainBoundsRect(proposedBounds)
        }

        var rect = super.constrainBoundsRect(proposedBounds)
        let docSize = documentView.bounds.size

        if rect.size.width > docSize.width {
            rect.origin.x = (docSize.width - rect.size.width) / 2
        } else {
            rect.origin.x = max(0, min(rect.origin.x, docSize.width - rect.size.width))
        }

        if rect.size.height > docSize.height {
            rect.origin.y = (docSize.height - rect.size.height) / 2
        } else {
            rect.origin.y = max(0, min(rect.origin.y, docSize.height - rect.size.height))
        }

        return rect
    }
}

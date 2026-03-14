//
//  WindowCoordinateSpaceView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import SwiftUI

struct WindowCoordinateSpaceView: NSViewRepresentable {
    @Binding var convertToScreen: ((CGRect) -> CGRect)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateConverter(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateConverter(nsView)
    }

    private func updateConverter(_ view: NSView) {
        DispatchQueue.main.async {
            self.convertToScreen = { rect in
                guard let window = view.window else { return rect }
                let contentRect = window.contentRect(forFrameRect: window.frame)
                let viewSize = view.bounds.size
                guard viewSize.width > 1, viewSize.height > 1 else { return rect }

                let scaleX = contentRect.width / viewSize.width
                let scaleY = contentRect.height / viewSize.height
                let screenRect = CGRect(
                    x: contentRect.minX + rect.minX * scaleX,
                    y: contentRect.maxY - rect.maxY * scaleY,
                    width: rect.width * scaleX,
                    height: rect.height * scaleY
                )
                return screenRect
            }
        }
    }
}

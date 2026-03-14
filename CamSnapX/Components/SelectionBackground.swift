//
//  SelectionBackground.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import SwiftUI

struct SelectionBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .selection
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    }
}

//
//  CaptureHistoryView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI
import AppKit

struct CaptureHistoryView: View {
    @ObservedObject var store: CaptureHistoryStore

    var body: some View {
        CaptureHistoryPanelView(store: store)
    }
}

#Preview {
    CaptureHistoryView(store: CaptureHistoryStore.shared)
}

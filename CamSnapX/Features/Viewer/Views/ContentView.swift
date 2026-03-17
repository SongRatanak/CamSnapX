//
//  ContentView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var historyStore = CaptureHistoryStore.shared
    @State private var draggedImage: NSImage? = nil
    @State private var isDragOver = false
    @State private var hasPreviousArea = CaptureAreaController.shared.hasPreviousArea

    var body: some View {
        MenuPopoverView(
            historyStore: historyStore,
            draggedImage: $draggedImage,
            isDragOver: $isDragOver,
            hasPreviousArea: $hasPreviousArea,
            onDismiss: { dismiss() }
        )
        .onAppear {
            hasPreviousArea = CaptureAreaController.shared.hasPreviousArea
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .captureAreaDidUpdate) {
                hasPreviousArea = CaptureAreaController.shared.hasPreviousArea
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 300, height: 600)
            .padding()
    }
}
#endif

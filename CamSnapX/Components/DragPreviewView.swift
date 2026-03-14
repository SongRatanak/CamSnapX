//
//  DragPreviewView.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import SwiftUI

struct DragPreviewView: View {
    let image: NSImage
    @Binding var isVisible: NSImage?

    @State private var dragOffset = CGSize.zero
    @State private var accumulatedOffset = CGSize.zero

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isVisible = nil
                }

            VStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 400, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    Button("Close") {
                        isVisible = nil
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding()
                }
            }
            .padding()
            .offset(
                x: accumulatedOffset.width + dragOffset.width,
                y: accumulatedOffset.height + dragOffset.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        accumulatedOffset.width += value.translation.width
                        accumulatedOffset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
        }
    }
}

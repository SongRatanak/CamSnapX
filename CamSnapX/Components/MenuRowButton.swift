//
//  MenuRowButton.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

struct MenuRowButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isHovering ? Color(nsColor: .selectedMenuItemTextColor) : Color(nsColor: .controlTextColor))
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Group {
                if isHovering {
                    SelectionBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Color.clear
                }
            }
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

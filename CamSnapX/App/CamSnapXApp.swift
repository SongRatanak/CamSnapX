//
//  CamSnapXApp.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

@main
struct CamSnapXApp: App {
    init() {
        ShortcutManager.shared.startMonitoring()
    }

    var body: some Scene {
        MenuBarExtra("CamSnapX", systemImage: "viewfinder") {
            ContentView()
        }
        .menuBarExtraStyle(.window)

    }
}

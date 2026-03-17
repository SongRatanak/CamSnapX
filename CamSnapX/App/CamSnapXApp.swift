//
//  CamSnapXApp.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import SwiftUI

final class CamSnapXAppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ShortcutManager.shared.startMonitoring()
        statusBarController = StatusBarController()
    }
}

@main
struct CamSnapXApp: App {
    @NSApplicationDelegateAdaptor(CamSnapXAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

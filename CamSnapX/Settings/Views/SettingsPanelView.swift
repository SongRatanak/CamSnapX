//
//  SettingsPanelView.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import Combine
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

final class SettingsPanelViewModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

struct SettingsPanelView: View {
    @ObservedObject var viewModel: SettingsPanelViewModel
    @State private var recordingAction: ShortcutAction? = nil
    @State private var recordingMonitor: Any? = nil
    @AppStorage("shortcut.scope") private var shortcutScopeRaw = ShortcutScope.appOnly.rawValue

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar
                .padding(.top, 12)

            Divider()
                .padding(.top, 8)

            // Content
            Group {
                switch viewModel.selectedTab {
                case .general:
                    generalTab
                case .shortcuts:
                    shortcutsTab
                case .about:
                    aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 460)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(
                        viewModel.selectedTab == tab
                            ? .primary
                            : .secondary
                    )
                    .frame(width: 72, height: 44)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                viewModel.selectedTab == tab
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()

            // App icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            // App name
            Text("CamSnapX")
                .font(.system(size: 22, weight: .bold))

            // Version
            Text(appVersion)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            // Copyright
            Text("\u{00A9} 2026 SongRatanak. All Rights Reserved.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()

            // Bottom links
            HStack(spacing: 0) {
                bottomLink("Acknowledgments") {}

                Spacer()

                bottomLink("What's New") {}
                bottomLinkDivider
                bottomLink("Visit Website") {}
                bottomLinkDivider
                bottomLink("Contact Us") {}
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func bottomLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private var bottomLinkDivider: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 6)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection("History") {
                    settingsRow("Auto-delete history") {
                        Picker("", selection: Binding(
                            get: { CaptureHistoryStore.shared.retentionDays ?? 0 },
                            set: { CaptureHistoryStore.shared.retentionDays = $0 == 0 ? nil : $0 }
                        )) {
                            Text("Never").tag(0)
                            Text("After 1 day").tag(1)
                            Text("After 3 days").tag(3)
                            Text("After 1 week").tag(7)
                            Text("After 1 month").tag(30)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }
                }

                settingsSection("Capture") {
                    settingsRow("Show preview after capture") {
                        Toggle("", isOn: .constant(true))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    settingsRow("Copy to clipboard") {
                        Toggle("", isOn: .constant(true))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    settingsRow("Play sound") {
                        Toggle("", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                settingsSection("Save") {
                    settingsRow("Save location") {
                        Text("Desktop")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }
            }
            .padding(24)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Shortcuts Tab (UI only)

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection("Shortcut Scope") {
                    settingsRow("Shortcut scope") {
                        Picker("", selection: $shortcutScopeRaw) {
                            Text("App Only").tag(ShortcutScope.appOnly.rawValue)
                            Text("Global").tag(ShortcutScope.global.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    settingsRow("Accessibility") {
                        Button("Open System Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                settingsSection("General") {
                    shortcutRow(.allInOne)
                    shortcutRow(.toggleDesktopIcons)
                    shortcutRow(.openCaptureHistory)
                    shortcutRow(.restoreLastCapture)
                }

                settingsSection("Screenshots") {
                    shortcutRow(.captureArea)
                    shortcutRow(.capturePreviousArea)
                    shortcutRow(.captureFullscreen)
                    shortcutRow(.captureWindow)
                    shortcutRow(.selfTimer)
                    shortcutRow(.captureAreaCopy)
                    shortcutRow(.captureAreaSave)
                }
            }
            .padding(24)
        }
        .onChange(of: shortcutScopeRaw) { _ in
            ShortcutManager.shared.requestAccessibilityIfNeeded()
            ShortcutManager.shared.updateMonitoring()
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        settingsRow(action.label) {
            Button(recordingAction == action ? "Type shortcut..." : (storedShortcut(for: action) ?? "Record shortcut")) {
                startRecording(action)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if let shortcut = ShortcutKey(event: event)?.displayString {
                saveShortcut(shortcut, for: action)
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        recordingAction = nil
    }

    private func storedShortcut(for action: ShortcutAction) -> String? {
        UserDefaults.standard.string(forKey: action.userDefaultsKey)
    }

    private func saveShortcut(_ value: String, for action: ShortcutAction) {
        UserDefaults.standard.set(value, forKey: action.userDefaultsKey)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
struct SettingsPanelView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsPanelView(viewModel: {
                let vm = SettingsPanelViewModel()
                vm.selectedTab = .about
                return vm
            }())
            .previewDisplayName("About")

            SettingsPanelView(viewModel: SettingsPanelViewModel())
                .previewDisplayName("General")
        }
    }
}
#endif

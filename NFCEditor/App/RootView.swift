import Foundation
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var state = app
        TabView(selection: $state.selectedTab) {
            ReadView()
                .tabItem { Label("Read", systemImage: "wave.3.right") }
                .tag(AppTab.read)
            WriteView()
                .tabItem { Label("Write", systemImage: "square.and.pencil") }
                .tag(AppTab.write)
            ToolsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(AppTab.tools)
            SavedView()
                .tabItem { Label("Saved", systemImage: "folder") }
                .tag(AppTab.saved)
        }
        .onAppear {
            Haptics.enabled = app.settings.hapticsEnabled
            applyScreenAwake(app.settings.keepScreenAwake)
            applyAppearance(app.settings.appearance)
            SettingsView.removeScanLogFile()
        }
        .onChange(of: app.settings.appearance) { _, newValue in
            applyAppearance(newValue)
        }
        .onChange(of: app.settings.verifyAfterWrite) { _, newValue in
            app.writeQueue.options.verifyAfterWrite = newValue
        }
        .onChange(of: app.settings.hapticsEnabled) { _, newValue in
            Haptics.enabled = newValue
        }
        .onChange(of: app.settings.keepScreenAwake) { _, newValue in
            applyScreenAwake(newValue)
        }
    }

    /// Set on the window rather than with preferredColorScheme so every sheet and alert follows it too.
    @MainActor
    private func applyAppearance(_ appearance: AppAppearance) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows {
            window.overrideUserInterfaceStyle = appearance.interfaceStyle
        }
    }

    @MainActor
    private func applyScreenAwake(_ enabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = enabled
    }
}

extension AppAppearance {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

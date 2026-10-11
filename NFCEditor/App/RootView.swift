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
        }
        .onChange(of: app.settings.hapticsEnabled) { _, newValue in
            Haptics.enabled = newValue
        }
        .onChange(of: app.settings.keepScreenAwake) { _, newValue in
            applyScreenAwake(newValue)
        }
    }

    @MainActor
    private func applyScreenAwake(_ enabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = enabled
    }
}

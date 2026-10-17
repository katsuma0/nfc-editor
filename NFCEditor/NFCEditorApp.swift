import Foundation
import SwiftUI

@main
struct NFCEditorApp: App {
    /// The shared instance, not a new one, so App Intents and the screens work on the same state.
    @State private var app = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

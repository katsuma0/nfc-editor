import Foundation
import SwiftUI

@main
struct NFCEditorApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

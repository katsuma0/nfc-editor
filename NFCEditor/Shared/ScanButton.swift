import Foundation
import SwiftUI

/// Big prominent button used by every tab for the primary NFC action. Disabled while `app.nfc.isBusy`.
struct ScanButton: View {
    @Environment(AppState.self) private var app

    private let title: String
    private let systemImage: String
    private let role: ButtonRole?
    private let action: () -> Void

    init(_ title: String, systemImage: String = "wave.3.right", role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(app.nfc.isBusy)
    }
}

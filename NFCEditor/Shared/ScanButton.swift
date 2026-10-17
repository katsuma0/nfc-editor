import Foundation
import SwiftUI

/// Big prominent button used by every tab for the primary NFC action. Disabled while `app.nfc.isBusy`.
struct ScanButton: View {
    @Environment(AppState.self) private var app

    private let title: String
    private let role: ButtonRole?
    private let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            // Plain text, not a Label: inside a List a Label gets an icon column that pushes the title off centre.
            Text(title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(app.nfc.isBusy)
        .padding(.vertical, 6)
    }
}

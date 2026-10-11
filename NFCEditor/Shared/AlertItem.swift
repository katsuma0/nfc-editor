import Foundation
import SwiftUI

struct AlertItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error) {
        let mapped = NFCEditorError.map(error)
        switch mapped {
        case .cancelled:
            title = "Cancelled"
        case .invalidInput:
            title = "Check the input"
        case .notSupportedOnChip, .unsupportedTag:
            title = "Not supported"
        case .capacityExceeded:
            title = "Too much data"
        case .readOnly:
            title = "Read only"
        case .authenticationFailed:
            title = "Wrong password"
        default:
            title = "Something went wrong"
        }
        message = mapped.errorDescription ?? "Something went wrong."
    }

    static func success(_ message: String) -> AlertItem {
        AlertItem(title: "Done", message: message)
    }
}

extension View {
    /// `.alert(item: $alert)` replacement that compiles cleanly on iOS 17: shows title + message with an OK button.
    func alertItem(_ item: Binding<AlertItem?>) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    item.wrappedValue = nil
                }
            }
        )
        return alert(
            item.wrappedValue?.title ?? "",
            isPresented: isPresented,
            presenting: item.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { current in
            Text(current.message)
        }
    }
}

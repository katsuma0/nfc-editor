import Foundation
import SwiftUI
import CoreNFC

/// Reads the NTAG read counter or the three Ultralight EV1 counters, and switches the NTAG counter on or off.
@MainActor
struct CounterToolView: View {
    @Environment(AppState.self) private var app
    @State private var lastRead: CounterResult?
    @State private var enableCounter = true
    @State private var password = Data()
    @State private var alert: AlertItem?

    var body: some View {
        Form {
            Section {
                ScanButton("Read counter") {
                    read()
                }
            } footer: {
                Text("NTAG 213, 215 and 216 have one counter that goes up every time the tag is read. MIFARE Ultralight EV1 has three counters that apps can only increase. Other chips have no counter.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let lastRead {
                Section {
                    LabeledContent("Chip", value: lastRead.chipName)
                    ForEach(lastRead.readings) { reading in
                        LabeledContent(CounterToolView.label(for: reading, in: lastRead), value: reading.value.formatted())
                    }
                } header: {
                    Text("Counter")
                } footer: {
                    Text("Read at \(lastRead.readAt.formatted(date: .omitted, time: .shortened)).")
                }
            }

            Section {
                Toggle("Count every read", isOn: $enableCounter)
                DisclosureGroup("Password") {
                    HexTextField("Password", data: $password, byteCount: 4)
                }
            } header: {
                Text("NFC counter")
            } footer: {
                Text("Only NTAG 213, 215 and 216 can switch their counter on or off. Choose the state you want, then hold the tag. Enter the password if the tag's configuration is password protected.")
            }

            Section {
                ScanButton(enableCounter ? "Enable counter" : "Disable counter") {
                    apply()
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Counter")
        .navigationBarTitleDisplayMode(.inline)
        .alertItem($alert)
    }

    private static func label(for reading: CounterReading, in result: CounterResult) -> String {
        result.readings.count == 1 ? "Read count" : "Counter \(reading.address)"
    }

    // MARK: Actions

    private func read() {
        Task { @MainActor in
            do {
                let result = try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: "Counter read."
                ) { session, tag -> CounterResult in
                    let (spec, _) = try await TagOperations.identify(session, tag)
                    guard spec.supportsCounter else {
                        throw NFCEditorError.notSupportedOnChip("\(spec.name) has no counter.")
                    }
                    // NTAG tags expose a single counter at address 2; Ultralight EV1 has counters 0, 1 and 2.
                    let addresses = spec.counterCount >= 3 ? [0, 1, 2] : [2]
                    var readings: [CounterReading] = []
                    for address in addresses {
                        let value = try await TagOperations.readCounter(session, tag, address: address)
                        readings.append(CounterReading(address: address, value: value))
                    }
                    return CounterResult(chipName: spec.name, readings: readings, readAt: Date())
                }
                lastRead = result
                Haptics.success()
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }

    private func apply() {
        if !password.isEmpty && password.count != 4 {
            alert = AlertItem(error: NFCEditorError.invalidInput("The password must be 4 bytes."))
            return
        }
        let enabled = enableCounter
        let currentPassword: Data? = password.count == 4 ? password : nil
        Task { @MainActor in
            do {
                try await app.nfc.run(
                    alertMessage: "Hold your iPhone near the tag.",
                    successMessage: enabled ? "Counter enabled." : "Counter disabled."
                ) { session, tag in
                    try await TagOperations.setCounter(session, tag, enabled: enabled, password: currentPassword)
                }
                Haptics.success()
                alert = AlertItem.success(enabled ? "The counter is now enabled." : "The counter is now disabled.")
            } catch {
                if NFCEditorError.map(error).isCancellation { return }
                Haptics.error()
                alert = AlertItem(error: error)
            }
        }
    }
}

private struct CounterReading: Identifiable, Hashable, Sendable {
    var address: Int
    var value: UInt32

    var id: Int { address }
}

private struct CounterResult: Hashable, Sendable {
    var chipName: String
    var readings: [CounterReading]
    var readAt: Date
}

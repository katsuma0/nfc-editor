import Foundation
import SwiftUI

/// Sheet that edits one record draft. The draft is copied in and handed back on Save.
struct RecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecordDraft
    @State private var showPassword = false

    private let onSave: (RecordDraft) -> Void

    init(draft: RecordDraft, onSave: @escaping (RecordDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                form
                statusSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(validationMessage != nil)
                }
            }
        }
    }

    // MARK: Bindings

    private func field(_ key: String) -> Binding<String> {
        Binding(
            get: { draft[key] },
            set: { newValue in draft[key] = newValue }
        )
    }

    private func flag(_ key: String) -> Binding<Bool> {
        Binding(
            get: { draft[key].lowercased() == "true" },
            set: { newValue in draft[key] = newValue ? "true" : "false" }
        )
    }

    private func choice<T: RawRepresentable>(_ key: String, fallback: T) -> Binding<T> where T.RawValue == String {
        Binding(
            get: { T(rawValue: draft[key]) ?? fallback },
            set: { newValue in draft[key] = newValue.rawValue }
        )
    }

    private var tnfBinding: Binding<TypeNameFormat> {
        Binding(
            get: {
                let raw = draft[DraftKey.tnf].trimmingCharacters(in: .whitespacesAndNewlines)
                return UInt8(raw).flatMap { TypeNameFormat(rawValue: $0) } ?? TypeNameFormat.wellKnown
            },
            set: { newValue in draft[DraftKey.tnf] = String(newValue.rawValue) }
        )
    }

    // MARK: Derived state

    private var validationMessage: String? {
        draft.validate()
    }

    private var sizeText: String {
        validationMessage == nil ? ByteFormatter.bytes(draft.encodedSize) : "Incomplete"
    }

    private var wifiAuth: WiFiCredential.Auth {
        WiFiCredential.Auth(rawValue: draft[DraftKey.auth]) ?? WiFiCredential.Auth.wpa2PSK
    }

    private var socialPlatform: SocialPlatform {
        SocialPlatform(rawValue: draft[DraftKey.platform]) ?? SocialPlatform.instagram
    }

    private var payloadIsHex: Bool {
        draft[DraftKey.payloadIsHex].lowercased() == "true"
    }

    private var trimmedHandle: String {
        draft[DraftKey.handle].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var handlePlaceholder: String {
        socialPlatform == .whatsapp ? "Phone number with country code" : "Username"
    }

    private var externalTypeFooter: String {
        let domain = draft[DraftKey.domain].trimmingCharacters(in: .whitespacesAndNewlines)
        let type = draft[DraftKey.externalType].trimmingCharacters(in: .whitespacesAndNewlines)
        if domain.isEmpty || type.isEmpty {
            return "The record type is written as domain:type, for example example.com:mytype."
        }
        return "The record type will be \(domain):\(type)."
    }

    // MARK: Form

    @ViewBuilder
    private var form: some View {
        switch draft.kind {
        case .text: textForm
        case .url: urlForm
        case .email: emailForm
        case .contact: contactForm
        case .phone: phoneForm
        case .sms: smsForm
        case .geo: geoForm
        case .address: addressForm
        case .wifi: wifiForm
        case .bluetooth: bluetoothForm
        case .social: socialForm
        case .app: appForm
        case .customURI: customURIForm
        case .customMIME: customMIMEForm
        case .external: externalForm
        case .raw, .handover, .unknown: rawForm
        case .empty: emptyForm
        case .smartPoster: smartPosterForm
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Size") {
                Text(sizeText)
            }
        } footer: {
            if let message = validationMessage {
                Text(message)
                    .foregroundStyle(.red)
            } else {
                Text("Size inside the NDEF message. The tag adds a few bytes of its own.")
            }
        }
    }

    // MARK: Text

    @ViewBuilder
    private var textForm: some View {
        Section("Text") {
            TextField("Text", text: field(DraftKey.text), axis: .vertical)
                .lineLimit(3...12)
        }
        Section {
            LabeledContent("Language") {
                TextField("en", text: field(DraftKey.language))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } footer: {
            Text("Language code such as en, fr or de. Readers use it to pick the right text.")
        }
    }

    // MARK: URL

    @ViewBuilder
    private var urlForm: some View {
        Section {
            TextField("https://example.com", text: field(DraftKey.url))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("URL")
        } footer: {
            Text("https:// is added when you leave it out.")
        }
    }

    // MARK: Email

    @ViewBuilder
    private var emailForm: some View {
        Section("Email") {
            TextField("To", text: field(DraftKey.email))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Subject", text: field(DraftKey.subject))
        }
        Section("Body") {
            TextField("Body", text: field(DraftKey.body), axis: .vertical)
                .lineLimit(3...10)
        }
    }

    // MARK: Contact

    @ViewBuilder
    private var contactForm: some View {
        Section("Name") {
            TextField("First name", text: field(DraftKey.firstName))
                .textContentType(.givenName)
            TextField("Last name", text: field(DraftKey.lastName))
                .textContentType(.familyName)
        }
        Section("Work") {
            TextField("Organization", text: field(DraftKey.organization))
                .textContentType(.organizationName)
            TextField("Job title", text: field(DraftKey.title))
                .textContentType(.jobTitle)
        }
        Section("Contact") {
            TextField("Phone", text: field(DraftKey.phone))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            TextField("Email", text: field(DraftKey.email))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Website", text: field(DraftKey.website))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        Section("Address") {
            TextField("Street, city, country", text: field(DraftKey.address), axis: .vertical)
                .lineLimit(1...4)
        }
        Section {
            TextField("Note", text: field(DraftKey.note), axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Text("Note")
        } footer: {
            Text("Enter at least a name, organization, phone or email.")
        }
    }

    // MARK: Phone and SMS

    @ViewBuilder
    private var phoneForm: some View {
        Section {
            TextField("+1 555 123 4567", text: field(DraftKey.phone))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        } header: {
            Text("Phone number")
        } footer: {
            Text("Include the country code so the number works everywhere.")
        }
    }

    @ViewBuilder
    private var smsForm: some View {
        Section("Phone number") {
            TextField("+1 555 123 4567", text: field(DraftKey.phone))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        }
        Section {
            TextField("Message", text: field(DraftKey.body), axis: .vertical)
                .lineLimit(3...10)
        } header: {
            Text("Message")
        } footer: {
            Text("The message is filled in but not sent until the person taps Send.")
        }
    }

    // MARK: Location and address

    @ViewBuilder
    private var geoForm: some View {
        Section("Coordinates") {
            LabeledContent("Latitude") {
                TextField("37.3349", text: field(DraftKey.latitude))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            }
            LabeledContent("Longitude") {
                TextField("-122.0090", text: field(DraftKey.longitude))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            }
        }
        Section {
            Picker("Opens in", selection: field(DraftKey.geoFormat)) {
                Text("Any maps app").tag("geo")
                Text("Apple Maps").tag("apple")
                Text("Google Maps").tag("google")
            }
        } footer: {
            Text("Any maps app writes a geo: link. The other choices write a web link to that service.")
        }
    }

    @ViewBuilder
    private var addressForm: some View {
        Section("Address") {
            TextField("1 Apple Park Way, Cupertino", text: field(DraftKey.address), axis: .vertical)
                .lineLimit(2...6)
                .textContentType(.fullStreetAddress)
        }
        Section {
            Picker("Opens in", selection: field(DraftKey.addressFormat)) {
                Text("Apple Maps").tag("apple")
                Text("Google Maps").tag("google")
                Text("Any maps app").tag("geo")
            }
        } footer: {
            Text("Any maps app writes a geo: search link. The other choices write a web link to that service.")
        }
    }

    // MARK: Wi-Fi

    @ViewBuilder
    private var wifiForm: some View {
        Section("Network") {
            TextField("Network name", text: field(DraftKey.ssid))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Security", selection: choice(DraftKey.auth, fallback: WiFiCredential.Auth.wpa2PSK)) {
                ForEach(WiFiCredential.Auth.allCases) { auth in
                    Text(auth.rawValue).tag(auth)
                }
            }
            if wifiAuth != .open {
                HStack {
                    Group {
                        if showPassword {
                            TextField("Password", text: field(DraftKey.password))
                        } else {
                            SecureField("Password", text: field(DraftKey.password))
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
                Picker("Encryption", selection: choice(DraftKey.encryption, fallback: WiFiCredential.Encryption.aes)) {
                    ForEach(WiFiCredential.Encryption.allCases) { encryption in
                        Text(encryption.rawValue).tag(encryption)
                    }
                }
            }
        }
        Section {
            Toggle("Hidden network", isOn: flag(DraftKey.hidden))
        } footer: {
            Text("The password is stored on the tag as plain text. Anyone who scans the tag can read it.")
        }
    }

    // MARK: Bluetooth

    @ViewBuilder
    private var bluetoothForm: some View {
        Section {
            TextField("AA:BB:CC:DD:EE:FF", text: field(DraftKey.mac))
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Device name (optional)", text: field(DraftKey.name))
        } header: {
            Text("Device")
        } footer: {
            Text("Find the address in the device's settings or on its label.")
        }
        Section {
            Toggle("Wrap in Handover Select (Android pairing)", isOn: flag(DraftKey.handover))
        } footer: {
            Text("Puts a Handover Select record in front of the pairing record, the NFC Forum pairing format that Android phones and many speakers and headsets look for. It adds a few bytes. iPhones ignore both records.")
        }
    }

    // MARK: Social

    @ViewBuilder
    private var socialForm: some View {
        Section("Profile") {
            Picker("Platform", selection: choice(DraftKey.platform, fallback: SocialPlatform.instagram)) {
                ForEach(SocialPlatform.allCases) { platform in
                    Text(platform.displayName).tag(platform)
                }
            }
            TextField(handlePlaceholder, text: field(DraftKey.handle))
                .keyboardType(socialPlatform == .whatsapp ? .phonePad : .asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        if !trimmedHandle.isEmpty {
            Section("Link") {
                Text(socialPlatform.url(handle: trimmedHandle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: Android app

    @ViewBuilder
    private var appForm: some View {
        Section {
            TextField("com.example.app", text: field(DraftKey.package))
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Android package name")
        } footer: {
            Text("Android phones open the app, or its Play Store page when it is not installed. iPhones ignore this record.")
        }
    }

    // MARK: Custom URI

    @ViewBuilder
    private var customURIForm: some View {
        Section {
            TextField("myapp://open", text: field(DraftKey.url))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("URI")
        } footer: {
            Text("Written exactly as typed. Use any scheme, for example tel:, mailto: or a custom app scheme.")
        }
    }

    // MARK: MIME and external

    @ViewBuilder
    private var customMIMEForm: some View {
        Section("MIME type") {
            TextField("text/plain", text: field(DraftKey.mime))
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        payloadSections
    }

    @ViewBuilder
    private var externalForm: some View {
        Section {
            TextField("example.com", text: field(DraftKey.domain))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("mytype", text: field(DraftKey.externalType))
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Type")
        } footer: {
            Text(externalTypeFooter)
        }
        payloadSections
    }

    /// Shared by MIME and external records: the payload as text or as hex bytes.
    @ViewBuilder
    private var payloadSections: some View {
        Section {
            Picker("Format", selection: flag(DraftKey.payloadIsHex)) {
                Text("Text").tag(false)
                Text("Hex").tag(true)
            }
            .pickerStyle(.segmented)
            if payloadIsHex {
                TextField("01 02 FF", text: field(DraftKey.payloadHex), axis: .vertical)
                    .lineLimit(3...10)
                    .font(.body.monospaced())
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } else {
                TextField("Payload", text: field(DraftKey.payloadText), axis: .vertical)
                    .lineLimit(3...10)
            }
        } header: {
            Text("Payload")
        } footer: {
            Text(payloadIsHex ? "Bytes as hex, for example 01 02 FF. Spaces are optional." : "Written as UTF-8 text.")
        }
    }

    // MARK: Raw

    /// Unchanged is left out because it is only valid inside a chunked record; a single record with it is malformed.
    private static let editableFormats = TypeNameFormat.allCases.filter { $0 != .unchanged }

    @ViewBuilder
    private var rawForm: some View {
        Section {
            Picker("Type name format", selection: tnfBinding) {
                ForEach(Self.editableFormats, id: \.rawValue) { tnf in
                    Text(tnf.label).tag(tnf)
                }
            }
        } footer: {
            Text("Well known is for NFC Forum types such as T and U. MIME media takes a MIME type. External takes domain:type.")
        }
        Section {
            TextField("Type, for example 55 for U", text: field(DraftKey.type))
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("ID (optional)", text: field(DraftKey.identifier))
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Header")
        } footer: {
            Text("Type and ID as hex bytes. Spaces are optional.")
        }
        Section {
            TextField("Payload as hex", text: field(DraftKey.payloadHex), axis: .vertical)
                .lineLimit(3...12)
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Payload")
        } footer: {
            Text("Leave empty for a record with no payload.")
        }
    }

    // MARK: Empty and smart poster

    private var emptyForm: some View {
        Section {
            Text("Nothing to edit.")
                .foregroundStyle(.secondary)
        } footer: {
            Text("An empty record clears the tag's data without changing its format.")
        }
    }

    @ViewBuilder
    private var smartPosterForm: some View {
        Section {
            TextField("https://example.com", text: field(DraftKey.url))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("URL")
        } footer: {
            Text("https:// is added when you leave it out.")
        }
        Section {
            TextField("Title (optional)", text: field(DraftKey.text))
            LabeledContent("Language") {
                TextField("en", text: field(DraftKey.language))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Title")
        } footer: {
            Text("A smart poster wraps the URL with a title that some readers show before opening it. iPhones open the URL.")
        }
    }
}

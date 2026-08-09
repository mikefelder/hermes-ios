import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    private let appIcon = AppIconController()

    var body: some View {
        List {
            if let profile = appModel.activeProfile {
                Section("Connection") {
                    NavigationLink {
                        ConnectionSettingsView(appModel: appModel, profile: profile)
                    } label: {
                        VStack(alignment: .leading, spacing: HermesSpacing.xSmall) {
                            Text(profile.name).font(.headline)
                            Text(profile.baseURL.host ?? profile.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(HermesTheme.textSecondary)
                        }
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        ConnectionStatusPill(state: appModel.connectionState)
                    }
                }

                Section("Agent") {
                    LabeledContent("Chat API", value: appModel.capabilities.supportsChatCompletions ? "Available" : "Not checked")
                    LabeledContent("Mobile adapter", value: appModel.capabilities.supportsMobileAdapter ? "Available" : "Not installed")
                    if let version = appModel.capabilities.observedVersion {
                        LabeledContent("Hermes version", value: version)
                    }
                }
            }

            Section("Appearance") {
                NavigationLink {
                    AppIconPickerView()
                } label: {
                    HStack(spacing: HermesSpacing.medium) {
                        Image(appIcon.current.previewAssetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("App icon")
                        Spacer()
                        Text(appIcon.current.displayName)
                            .foregroundStyle(HermesTheme.textSecondary)
                    }
                }
            }

            Section("Privacy") {
                Label("Password stored in device-only Keychain", systemImage: "key.fill")
                Label("App content hidden when inactive", systemImage: "eye.slash.fill")
            }

            Section("About") {
                LabeledContent("App version", value: appVersion)
                NavigationLink("Development specification") {
                    FeaturePlaceholderView(
                        title: "Specification",
                        symbol: "doc.text",
                        message: "The complete product and engineering specifications are included in the repository."
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HermesTheme.canvas)
        .foregroundStyle(HermesTheme.textPrimary)
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

struct ConnectionSettingsView: View {
    @Bindable var appModel: AppModel
    @State private var editor: ConnectionEditorModel
    @State private var isConfirmingForget = false
    @State private var forgetError: String?
    @Environment(\.dismiss) private var dismiss

    init(appModel: AppModel, profile: ServerProfile) {
        self.appModel = appModel
        _editor = State(initialValue: ConnectionEditorModel(appModel: appModel, profile: profile))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: HermesSpacing.xLarge) {
                ConnectionFormView(model: editor, saveTitle: "Save connection") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: HermesSpacing.medium) {
                    Text("Forget this server")
                        .font(.headline)
                    Text("Removes the URL, username, password, capabilities, and local server state from this iPhone. It does not delete data from Hermes.")
                        .font(.callout)
                        .foregroundStyle(HermesTheme.textSecondary)
                    Button("Forget server", role: .destructive) {
                        isConfirmingForget = true
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("forgetServerButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hermesCard()
            }
            .frame(maxWidth: 680)
            .padding(HermesSpacing.standard)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .hermesScreen()
        .confirmationDialog(
            "Forget this server?",
            isPresented: $isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget server", role: .destructive) {
                Task {
                    do {
                        try await appModel.forgetServer()
                        dismiss()
                    } catch {
                        forgetError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved Keychain password and local connection settings.")
        }
        .alert("Could not forget server", isPresented: Binding(
            get: { forgetError != nil },
            set: { if !$0 { forgetError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(forgetError ?? "")
        }
    }
}

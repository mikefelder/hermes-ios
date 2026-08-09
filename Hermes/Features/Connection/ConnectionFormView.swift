import SwiftUI

struct ConnectionFormView: View {
    @Bindable var model: ConnectionEditorModel
    let saveTitle: String
    let onSaved: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case name, url, username, password
    }

    private var usesBearer: Bool {
        model.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var secretTitle: String {
        usesBearer ? "API key" : "Password"
    }

    private var secretDetail: String {
        if model.hasStoredCredential && !model.hasSavedPassword {
            return usesBearer
                ? "The saved password does not apply to an API key. Enter your Hermes API key."
                : "The saved API key does not apply to a password. Enter your password."
        }
        return usesBearer
            ? "Your Hermes API key, sent as a Bearer token. Stored only in this iPhone's Keychain."
            : "Stored only in this iPhone's Keychain"
    }

    var body: some View {
        VStack(spacing: HermesSpacing.large) {
            fields
            if !model.checks.isEmpty {
                ConnectionTestResultsView(checks: model.checks)
            }
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(HermesTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("connectionError")
            }
            actions
        }
    }

    private var fields: some View {
        VStack(spacing: HermesSpacing.standard) {
            fieldLabel("Agent name", detail: "A private label stored on this iPhone")
            TextField("Hermes", text: $model.name)
                .textContentType(.name)
                .focused($focusedField, equals: .name)
                .hermesTextField()
                .accessibilityIdentifier("serverNameField")

            fieldLabel("Server URL", detail: "Your Hermes API address, including its port")
            TextField("https://hermes.example.ts.net:8443", text: $model.urlText)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .url)
                .hermesTextField()
                .accessibilityIdentifier("serverURLField")

            fieldLabel("Username", detail: "Leave blank to sign in with a Hermes API key instead")
            TextField("Username (optional)", text: $model.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .hermesTextField()
                .accessibilityIdentifier("usernameField")

            fieldLabel(
                secretTitle,
                detail: model.hasSavedPassword && model.password.isEmpty
                    ? "A secret is saved in Keychain. Leave blank to keep it."
                    : secretDetail
            )
            HStack(spacing: HermesSpacing.small) {
                Group {
                    if model.isPasswordVisible {
                        TextField(secretTitle, text: $model.password)
                    } else {
                        SecureField(secretTitle, text: $model.password)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .password)
                .accessibilityIdentifier("passwordField")

                Button {
                    model.isPasswordVisible.toggle()
                } label: {
                    Image(systemName: model.isPasswordVisible ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPasswordVisible ? "Hide secret" : "Show secret")
            }
            .padding(.leading, HermesSpacing.medium)
            .background(HermesTheme.raisedSurface, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                    .stroke(HermesTheme.border, lineWidth: 1)
            }
        }
        .hermesCard()
    }

    private var actions: some View {
        VStack(spacing: HermesSpacing.medium) {
            Button {
                focusedField = nil
                Task { await model.testConnection() }
            } label: {
                HStack {
                    if model.isTesting { ProgressView().tint(HermesTheme.canvas) }
                    Text(model.isTesting ? "Testing connection…" : "Test connection")
                        .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(HermesTheme.textPrimary)
            .foregroundStyle(HermesTheme.canvas)
            .disabled(!model.canTest)
            .accessibilityIdentifier("testConnectionButton")

            Button {
                Task {
                    do {
                        try await model.save()
                        onSaved()
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if model.isSaving { ProgressView() }
                    Text(saveTitle).frame(maxWidth: .infinity)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canSave)
            .accessibilityIdentifier("saveConnectionButton")

            Text("Saving is enabled after these exact settings pass the connection test.")
                .font(.caption)
                .foregroundStyle(HermesTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func fieldLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xSmall) {
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(HermesTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConnectionTestResultsView: View {
    let checks: [ConnectionCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.medium) {
            Text("Connection test")
                .font(.headline)
            ForEach(checks) { check in
                HStack(alignment: .top, spacing: HermesSpacing.medium) {
                    stateIcon(check.state)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: HermesSpacing.xSmall) {
                        Text(check.stage.title).font(.subheadline.weight(.semibold))
                        if let detail = detail(check.state) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(HermesTheme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hermesCard()
        .accessibilityIdentifier("connectionTestResults")
    }

    @ViewBuilder
    private func stateIcon(_ state: ConnectionCheckState) -> some View {
        switch state {
        case .running:
            ProgressView().tint(HermesTheme.warning)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(HermesTheme.success)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(HermesTheme.danger)
        }
    }

    private func detail(_ state: ConnectionCheckState) -> String? {
        switch state {
        case .running: "Checking…"
        case let .passed(detail): detail
        case let .failed(message): message
        }
    }
}

private extension View {
    func hermesTextField() -> some View {
        padding(.horizontal, HermesSpacing.medium)
            .frame(minHeight: 48)
            .background(HermesTheme.raisedSurface, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                    .stroke(HermesTheme.border, lineWidth: 1)
            }
    }
}

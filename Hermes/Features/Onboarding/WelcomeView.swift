import SwiftUI

struct WelcomeView: View {
    @State private var editor: ConnectionEditorModel

    init(appModel: AppModel) {
        _editor = State(initialValue: ConnectionEditorModel(appModel: appModel))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: HermesSpacing.xLarge) {
                header
                ConnectionFormView(model: editor, saveTitle: "Connect to Hermes") {}
                privacyNote
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, HermesSpacing.standard)
            .padding(.vertical, HermesSpacing.xLarge)
        }
        .scrollDismissesKeyboard(.interactively)
        .hermesScreen()
    }

    private var header: some View {
        VStack(spacing: HermesSpacing.standard) {
            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(HermesTheme.textPrimary)
                .accessibilityHidden(true)
            Text("Hermes")
                .font(.largeTitle.weight(.semibold))
            Text("Your agent, wherever you are.")
                .font(.title3)
                .foregroundStyle(HermesTheme.textSecondary)
            Text("Connect securely to the Hermes instance running in your Azure environment. Tailscale must be active on this iPhone.")
                .font(.body)
                .foregroundStyle(HermesTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var privacyNote: some View {
        Label {
            Text("Your conversations go directly to your private server. The app never stores your password outside Keychain.")
        } icon: {
            Image(systemName: "lock.shield.fill")
        }
        .font(.footnote)
        .foregroundStyle(HermesTheme.textSecondary)
        .hermesCard()
    }
}

#Preview {
    WelcomeView(appModel: AppModel(environment: .production()))
}

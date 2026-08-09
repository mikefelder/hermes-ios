import SwiftUI

struct RootView: View {
    @Bindable var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if appModel.isRestoring {
                    ProgressView("Restoring Hermes…")
                        .tint(HermesTheme.textPrimary)
                        .foregroundStyle(HermesTheme.textPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(HermesTheme.canvas)
                } else if appModel.activeProfile == nil {
                    WelcomeView(appModel: appModel)
                } else {
                    MainTabView(appModel: appModel)
                }
            }

            if scenePhase != .active {
                PrivacyCoverView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .task { await appModel.restore() }
        .alert("Hermes", isPresented: Binding(
            get: { appModel.presentedError != nil },
            set: { if !$0 { appModel.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appModel.presentedError ?? "")
        }
    }
}

struct MainTabView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        TabView {
            NavigationStack {
                ChatHomeView(appModel: appModel)
            }
            .tabItem { Label("Chat", systemImage: "message") }

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Sessions",
                    symbol: "clock.arrow.circlepath",
                    message: "Persistent session browsing arrives in the next development milestone."
                )
            }
            .tabItem { Label("Sessions", systemImage: "clock.arrow.circlepath") }

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Automations",
                    symbol: "calendar.badge.clock",
                    message: "Scheduled Hermes work will appear here after the mobile adapter is connected."
                )
            }
            .tabItem { Label("Automations", systemImage: "calendar.badge.clock") }

            NavigationStack {
                SettingsView(appModel: appModel)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(HermesTheme.textPrimary)
        .toolbarBackground(HermesTheme.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct ChatHomeView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: HermesSpacing.large) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .medium))
                .accessibilityHidden(true)
            Text("Ready for Hermes")
                .font(.title2.weight(.semibold))
            Text("The secure connection foundation is configured. Streaming chat is the next implementation milestone.")
                .foregroundStyle(HermesTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            ConnectionStatusPill(state: appModel.connectionState)
            Spacer()
        }
        .padding(HermesSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(appModel.activeProfile?.name ?? "Hermes")
        .hermesScreen()
    }
}

struct FeaturePlaceholderView: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .navigationTitle(title)
            .foregroundStyle(HermesTheme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .hermesScreen()
    }
}

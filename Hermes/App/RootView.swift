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

    @State private var selectedTab = Tab.chat
    @State private var conversation: ChatConversationModel?

    private enum Tab: Hashable {
        case chat, sessions, automations, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                if let conversation {
                    ChatView(appModel: appModel, conversation: conversation)
                }
            }
            .tabItem { Label("Chat", systemImage: "message") }
            .tag(Tab.chat)

            NavigationStack {
                SessionsView(appModel: appModel) { sessionID in
                    selectedTab = .chat
                    Task { await conversation?.open(sessionID: sessionID) }
                } onSessionDeleted: { sessionID in
                    conversation?.sessionWasDeleted(sessionID)
                }
            }
            .tabItem { Label("Sessions", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.sessions)

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Automations",
                    symbol: "calendar.badge.clock",
                    message: "Scheduled Hermes work will appear here after the mobile adapter is connected."
                )
            }
            .tabItem { Label("Automations", systemImage: "calendar.badge.clock") }
            .tag(Tab.automations)

            NavigationStack {
                SettingsView(appModel: appModel)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .tint(HermesTheme.textPrimary)
        .toolbarBackground(HermesTheme.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            if conversation == nil {
                conversation = ChatConversationModel(appModel: appModel)
            }
        }
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

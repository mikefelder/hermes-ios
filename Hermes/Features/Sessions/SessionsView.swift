import SwiftUI

/// Lists the agent's sessions, whichever client created them.
@MainActor
@Observable
final class SessionsListModel {
    private(set) var sessions: [SessionSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var isAvailable: Bool {
        appModel.environment.sessionsClient != nil && appModel.capabilities.supportsSessions
    }

    func load() async {
        guard let client = appModel.environment.sessionsClient,
              let profile = appModel.activeProfile else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let password = try await appModel.passwordForActiveProfile() ?? ""
            sessions = try await client.sessions(limit: 50, profile: profile, password: password)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct SessionsView: View {
    @Bindable var appModel: AppModel
    let onOpen: (String) -> Void

    @State private var model: SessionsListModel

    init(appModel: AppModel, onOpen: @escaping (String) -> Void) {
        self.appModel = appModel
        self.onOpen = onOpen
        _model = State(initialValue: SessionsListModel(appModel: appModel))
    }

    var body: some View {
        Group {
            if !model.isAvailable {
                ContentUnavailableView(
                    "Sessions unavailable",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("This Hermes server does not expose session resources.")
                )
            } else if model.sessions.isEmpty && model.isLoading {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh sessions")
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .hermesScreen()
    }

    private var list: some View {
        List {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(HermesTheme.warning)
                    .listRowBackground(HermesTheme.surface)
            }
            ForEach(model.sessions) { session in
                Button {
                    onOpen(session.id)
                } label: {
                    SessionRow(session: session)
                }
                .listRowBackground(HermesTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xSmall) {
            Text(session.title ?? session.preview ?? "Untitled session")
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: HermesSpacing.small) {
                if let source = session.source {
                    Text(source.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .padding(.horizontal, HermesSpacing.small)
                        .padding(.vertical, 2)
                        .background(HermesTheme.raisedSurface, in: Capsule())
                }
                Text("\(session.messageCount) messages")
                    .font(.caption)
                    .foregroundStyle(HermesTheme.textSecondary)
                if let toolCallCount = session.toolCallCount, toolCallCount > 0 {
                    Text("\(toolCallCount) tool calls")
                        .font(.caption)
                        .foregroundStyle(HermesTheme.textSecondary)
                }
            }
        }
        .padding(.vertical, HermesSpacing.xSmall)
        .foregroundStyle(HermesTheme.textPrimary)
        .accessibilityElement(children: .combine)
    }
}

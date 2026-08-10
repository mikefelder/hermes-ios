import SwiftUI

/// Lists the agent's sessions, whichever client created them.
@MainActor
@Observable
final class SessionsListModel {
    private(set) var sessions: [SessionSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// Lets the open conversation clear itself when its session is removed.
    var onSessionDeleted: ((String) -> Void)?

    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var isAvailable: Bool {
        appModel.environment.sessionsClient != nil && appModel.capabilities.supportsSessions
    }

    var canFork: Bool {
        appModel.capabilities.supportsSessionFork
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

    func rename(_ session: SessionSummary, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.title else { return }
        await mutate { client, profile, password in
            let updated = try await client.rename(
                id: session.id,
                title: trimmed,
                profile: profile,
                password: password
            )
            if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
                // Trust the local title if the server echoes the session without one.
                self.sessions[index].title = updated.title ?? trimmed
            }
        }
    }

    /// Removes the row immediately and restores it if the server refuses.
    func delete(_ session: SessionSummary) async {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let removed = sessions.remove(at: index)
        await mutate(
            onFailure: { self.sessions.insert(removed, at: min(index, self.sessions.count)) },
            work: { client, profile, password in
                try await client.delete(id: session.id, profile: profile, password: password)
                self.onSessionDeleted?(session.id)
            }
        )
    }

    func fork(_ session: SessionSummary) async -> String? {
        var forkedID: String?
        await mutate { client, profile, password in
            let forked = try await client.fork(id: session.id, profile: profile, password: password)
            forkedID = forked.id
            self.sessions.insert(forked, at: 0)
        }
        return forkedID
    }

    private func mutate(
        onFailure: @MainActor () -> Void = {},
        work: (any SessionServicing, ServerProfile, String) async throws -> Void
    ) async {
        guard let client = appModel.environment.sessionsClient,
              let profile = appModel.activeProfile else { return }
        do {
            let password = try await appModel.passwordForActiveProfile() ?? ""
            try await work(client, profile, password)
            errorMessage = nil
        } catch {
            onFailure()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct SessionsView: View {
    @Bindable var appModel: AppModel
    let onOpen: (String) -> Void
    var onSessionDeleted: ((String) -> Void)?

    @State private var model: SessionsListModel
    @State private var renaming: SessionSummary?
    @State private var renameText = ""
    @State private var pendingDeletion: SessionSummary?

    init(
        appModel: AppModel,
        onOpen: @escaping (String) -> Void,
        onSessionDeleted: ((String) -> Void)? = nil
    ) {
        self.appModel = appModel
        self.onOpen = onOpen
        self.onSessionDeleted = onSessionDeleted
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
        .task {
            model.onSessionDeleted = onSessionDeleted
            await model.load()
        }
        .refreshable { await model.load() }
        .alert("Rename session", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let session = renaming {
                    Task { await model.rename(session, to: renameText) }
                }
                renaming = nil
            }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let session = pendingDeletion {
                    Task { await model.delete(session) }
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The transcript is removed from the server and cannot be recovered.")
        }
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        beginRename(session)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(HermesTheme.raisedSurface)
                }
                .contextMenu {
                    Button {
                        beginRename(session)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    if model.canFork {
                        Button {
                            Task {
                                if let forkedID = await model.fork(session) {
                                    onOpen(forkedID)
                                }
                            }
                        } label: {
                            Label("Duplicate to new session", systemImage: "arrow.triangle.branch")
                        }
                    }
                    Button(role: .destructive) {
                        pendingDeletion = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func beginRename(_ session: SessionSummary) {
        renameText = session.title ?? ""
        renaming = session
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
                if session.isBranch {
                    Label("Branch", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .padding(.horizontal, HermesSpacing.small)
                        .padding(.vertical, 2)
                        .background(HermesTheme.raisedSurface, in: Capsule())
                }
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

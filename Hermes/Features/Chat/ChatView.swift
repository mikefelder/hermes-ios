import SwiftUI

struct ChatView: View {
    @Bindable var appModel: AppModel
    @Bindable var conversation: ChatConversationModel
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcript
            composer
        }
        .navigationTitle(appModel.activeProfile?.name ?? "Hermes")
        .task { await conversation.restorePendingWork() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    conversation.clear()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(conversation.isEmpty)
                .accessibilityLabel("New conversation")
            }
        }
        .hermesScreen()
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HermesSpacing.medium) {
                    if conversation.isEmpty {
                        emptyState
                    }
                    ForEach(conversation.messages) { message in
                        ChatBubble(role: message.role, text: message.content)
                            .id(message.id)
                    }
                    if !conversation.streamingText.isEmpty {
                        ChatBubble(role: .assistant, text: conversation.streamingText)
                            .id(streamingAnchor)
                    } else if conversation.isStreaming {
                        TypingIndicator(toolName: conversation.activeToolName)
                            .id(streamingAnchor)
                    }
                    if let approval = conversation.pendingApproval {
                        ApprovalCard(request: approval) { choice in
                            Task { await conversation.respondToApproval(choice: choice) }
                        }
                        .id(approvalAnchor)
                    }
                    if let errorMessage = conversation.errorMessage {
                        VStack(alignment: .leading, spacing: HermesSpacing.small) {
                            Label(errorMessage, systemImage: conversation.isOutcomeUnknown
                                ? "questionmark.circle.fill"
                                : "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(HermesTheme.warning)
                            if conversation.canRetry {
                                Button("Send again") { conversation.retry() }
                                    .font(.callout.weight(.semibold))
                                    .accessibilityIdentifier("chatRetryButton")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("chatError")
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(HermesSpacing.standard)
            }
            .onChange(of: conversation.messages.count) { _, _ in scroll(proxy) }
            .onChange(of: conversation.streamingText) { _, _ in scroll(proxy) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: HermesSpacing.small) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .medium))
                .accessibilityHidden(true)
            Text("Ask Hermes anything")
                .font(.title3.weight(.semibold))
            Text("Messages are sent to your own agent over the connection you configured.")
                .font(.callout)
                .foregroundStyle(HermesTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HermesSpacing.xLarge)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: HermesSpacing.small) {
            TextField("Message Hermes", text: $conversation.draft, axis: .vertical)
                .lineLimit(1...6)
                .textInputAutocapitalization(.sentences)
                .focused($isComposerFocused)
                .padding(HermesSpacing.medium)
                .background(HermesTheme.raisedSurface, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                        .stroke(HermesTheme.border, lineWidth: 1)
                }
                .accessibilityIdentifier("chatComposer")

            Button {
                if conversation.isStreaming {
                    conversation.stop()
                } else {
                    isComposerFocused = false
                    conversation.send()
                }
            } label: {
                Image(systemName: conversation.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(sendBackground, in: Circle())
                    .foregroundStyle(HermesTheme.canvas)
            }
            .disabled(!conversation.isStreaming && !conversation.canSend)
            .accessibilityLabel(conversation.isStreaming ? "Disconnect from response" : "Send message")
            .accessibilityIdentifier("chatSendButton")
        }
        .padding(HermesSpacing.standard)
        .background(HermesTheme.surface)
    }

    private var sendBackground: Color {
        if conversation.isStreaming { return HermesTheme.warning }
        return conversation.canSend ? HermesTheme.agent : HermesTheme.border
    }

    private var streamingAnchor: String { "streaming" }
    private var approvalAnchor: String { "approval" }
    private var bottomAnchor: String { "bottom" }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}

private struct ChatBubble: View {
    let role: ChatRole
    let text: String

    private var isUser: Bool { role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: HermesSpacing.xLarge) }
            content
                .padding(HermesSpacing.medium)
                .background(
                    isUser ? HermesTheme.agent.opacity(0.18) : HermesTheme.surface,
                    in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                        .stroke(HermesTheme.border, lineWidth: 1)
                }
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: HermesSpacing.xLarge) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isUser ? "You said" : "Hermes said")
    }

    @ViewBuilder
    private var content: some View {
        if isUser {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MarkdownMessageView(blocks: MarkdownParser().parse(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline approval prompt. The command is shown in full because the user is being
/// asked to authorise exactly this action, and it is rendered as inert text.
private struct ApprovalCard: View {
    let request: ApprovalRequest
    let respond: (String) -> Void

    @State private var confirmAlways = false

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.small) {
            Label("Approval required", systemImage: "exclamationmark.shield.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(HermesTheme.warning)

            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(HermesTheme.textSecondary)
            }

            if !request.command.isEmpty {
                ScrollView(.horizontal) {
                    Text(request.command)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(HermesSpacing.small)
                }
                .background(HermesTheme.canvas, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
            }

            HStack(spacing: HermesSpacing.small) {
                Button("Allow once") { respond("once") }
                    .buttonStyle(.borderedProminent)
                    .tint(HermesTheme.agent)
                Button("Deny", role: .destructive) { respond("deny") }
                    .buttonStyle(.bordered)
                Spacer()
                if request.allowsSession || request.allowsAlways {
                    Menu {
                        if request.allowsSession {
                            Button("Allow for this session") { respond("session") }
                        }
                        if request.allowsAlways {
                            Button("Always allow…") { confirmAlways = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More approval options")
                }
            }
        }
        .padding(HermesSpacing.medium)
        .background(HermesTheme.surface, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                .stroke(HermesTheme.warning.opacity(0.6), lineWidth: 1)
        }
        .confirmationDialog(
            "Always allow this action?",
            isPresented: $confirmAlways,
            titleVisibility: .visible
        ) {
            Button("Always allow", role: .destructive) { respond("always") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This writes a permanent allowlist entry on the Hermes server.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Approval required")
    }
}

private struct TypingIndicator: View {
    var toolName: String?

    var body: some View {
        HStack(spacing: HermesSpacing.small) {
            ProgressView().tint(HermesTheme.textSecondary)
            Text(toolName.map { "Running \($0)…" } ?? "Hermes is working…")
                .font(.callout)
                .foregroundStyle(HermesTheme.textSecondary)
        }
        .padding(HermesSpacing.medium)
        .accessibilityLabel(toolName.map { "Hermes is running \($0)" } ?? "Hermes is responding")
    }
}

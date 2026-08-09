import SwiftUI

struct ChatView: View {
    @Bindable var appModel: AppModel
    @State private var conversation: ChatConversationModel
    @FocusState private var isComposerFocused: Bool

    init(appModel: AppModel) {
        self.appModel = appModel
        _conversation = State(initialValue: ChatConversationModel(appModel: appModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            composer
        }
        .navigationTitle(appModel.activeProfile?.name ?? "Hermes")
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
                        TypingIndicator()
                            .id(streamingAnchor)
                    }
                    if let errorMessage = conversation.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(HermesTheme.warning)
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
            .accessibilityLabel(conversation.isStreaming ? "Stop response" : "Send message")
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
            Text(text)
                .textSelection(.enabled)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You said" : "Hermes said")
        .accessibilityValue(text)
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: HermesSpacing.small) {
            ProgressView().tint(HermesTheme.textSecondary)
            Text("Hermes is working…")
                .font(.callout)
                .foregroundStyle(HermesTheme.textSecondary)
        }
        .padding(HermesSpacing.medium)
        .accessibilityLabel("Hermes is responding")
    }
}

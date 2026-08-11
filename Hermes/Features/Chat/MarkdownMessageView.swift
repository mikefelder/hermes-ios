import SwiftUI

/// Renders parsed Markdown blocks.
///
/// Links are confirmed before opening and only HTTPS destinations are offered, so
/// assistant output can never navigate the app somewhere on its own.
struct MarkdownMessageView: View {
    let blocks: [MarkdownBlock]

    @State private var pendingLink: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.small) {
            ForEach(blocks) { block in
                view(for: block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard MarkdownSanitizer.isAllowed(url) else { return .discarded }
            pendingLink = url
            return .handled
        })
        .confirmationDialog(
            pendingLink?.host ?? "Open link",
            isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingLink {
                Link("Open in browser", destination: pendingLink)
                Button("Copy link") { UIPasteboard.general.string = pendingLink.absoluteString }
            }
            Button("Cancel", role: .cancel) { pendingLink = nil }
        } message: {
            Text(pendingLink?.absoluteString ?? "")
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, inline):
            inlineText(inline)
                .font(headingFont(level))
                .accessibilityAddTraits(.isHeader)

        case let .paragraph(inline):
            inlineText(inline)

        case let .bulletList(items):
            VStack(alignment: .leading, spacing: HermesSpacing.xSmall) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", content: item)
                }
            }

        case let .orderedList(items):
            VStack(alignment: .leading, spacing: HermesSpacing.xSmall) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(marker: "\(index + 1).", content: item)
                }
            }

        case let .quote(lines):
            HStack(alignment: .top, spacing: HermesSpacing.small) {
                Rectangle()
                    .fill(HermesTheme.agent.opacity(0.6))
                    .frame(width: 3)
                    .accessibilityHidden(true)
                inlineText(lines.joined(separator: "\n"))
                    .foregroundStyle(HermesTheme.textSecondary)
            }

        case let .code(language, content):
            CodeBlockView(language: language, content: content)

        case let .table(headers, rows):
            MarkdownTableView(headers: headers, rows: rows)

        case .rule:
            Divider().overlay(HermesTheme.border)
        }
    }

    private func listRow(marker: String, content: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HermesSpacing.small) {
            Text(marker)
                .monospacedDigit()
                .foregroundStyle(HermesTheme.textSecondary)
                .accessibilityHidden(true)
            inlineText(content)
        }
    }

    private func inlineText(_ markdown: String) -> some View {
        Text(MarkdownInline.attributed(markdown))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}

/// Builds inline attributed text and removes links the app refuses to open.
nonisolated enum MarkdownInline {
    static func attributed(_ markdown: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(markdown)
        }
        for run in attributed.runs {
            guard let link = run.link else { continue }
            if !MarkdownSanitizer.isAllowed(link) {
                attributed[run.range].link = nil
            }
        }
        return attributed
    }
}

/// Monospaced, horizontally scrolling code with a language label and copy action.
struct CodeBlockView: View {
    let language: String?
    let content: String

    @State private var isExpanded = false

    /// Long tool output is collapsed so one large block cannot bury the transcript.
    private let collapsedLineLimit = 18

    private var lines: [String] { content.components(separatedBy: "\n") }
    private var isCollapsible: Bool { lines.count > collapsedLineLimit }

    private var visibleContent: String {
        guard isCollapsible, !isExpanded else { return content }
        return lines.prefix(collapsedLineLimit).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HermesTheme.textSecondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = content
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, HermesSpacing.medium)
            .padding(.vertical, HermesSpacing.small)

            ScrollView(.horizontal) {
                Text(visibleContent)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(.horizontal, HermesSpacing.medium)
                    .padding(.bottom, HermesSpacing.small)
            }

            if isCollapsible {
                Button(isExpanded ? "Show less" : "Show all \(lines.count) lines") {
                    isExpanded.toggle()
                }
                .font(.caption)
                .padding(.horizontal, HermesSpacing.medium)
                .padding(.bottom, HermesSpacing.small)
            }
        }
        .background(HermesTheme.canvas, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                .stroke(HermesTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.map { "\($0) code block" } ?? "Code block")
    }
}

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                row(headers, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    Divider().overlay(HermesTheme.border)
                    row(cells, isHeader: false)
                }
            }
            .padding(HermesSpacing.small)
        }
        .background(HermesTheme.canvas, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                .stroke(HermesTheme.border, lineWidth: 1)
        }
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: HermesSpacing.medium) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(MarkdownInline.attributed(cell))
                    .font(isHeader ? .callout.weight(.semibold) : .callout)
                    .frame(minWidth: 64, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, HermesSpacing.xSmall)
    }
}

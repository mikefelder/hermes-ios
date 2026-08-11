import SwiftUI
import UIKit

/// The set of app icons the user can choose between. `seal` is the primary icon
/// (no alternate name); the others map to asset-catalog alternate app icons.
nonisolated enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    case seal
    case luminous
    case engraved
    case signal
    case original

    var id: String { rawValue }

    /// The asset-catalog alternate icon name, or `nil` for the primary icon.
    var alternateIconName: String? {
        switch self {
        case .seal: nil
        case .luminous: "AppIcon-Luminous"
        case .engraved: "AppIcon-Engraved"
        case .signal: "AppIcon-Signal"
        case .original: "AppIcon-Original"
        }
    }

    var displayName: String {
        switch self {
        case .seal: "Orbital Seal"
        case .luminous: "Luminous Agent"
        case .engraved: "Orbital Engraved"
        case .signal: "Signal Mark"
        case .original: "Original Agent"
        }
    }

    /// Name of the imageset used for the picker thumbnail.
    var previewAssetName: String {
        switch self {
        case .seal: "IconPreview-Seal"
        case .luminous: "IconPreview-Luminous"
        case .engraved: "IconPreview-Engraved"
        case .signal: "IconPreview-Signal"
        case .original: "IconPreview-Original"
        }
    }

    /// Resolve the option currently applied from the active alternate icon name.
    static func current(alternateIconName: String?) -> AppIconOption {
        allCases.first { $0.alternateIconName == alternateIconName } ?? .seal
    }
}

/// Thin wrapper over `UIApplication` alternate-icon APIs, isolated to the main actor.
@MainActor
struct AppIconController {
    var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    var current: AppIconOption {
        AppIconOption.current(alternateIconName: UIApplication.shared.alternateIconName)
    }

    func apply(_ option: AppIconOption) async throws {
        guard UIApplication.shared.alternateIconName != option.alternateIconName else { return }
        try await UIApplication.shared.setAlternateIconName(option.alternateIconName)
    }
}

struct AppIconPickerView: View {
    private let controller = AppIconController()
    @State private var selection: AppIconOption = .seal
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        row(for: option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appIcon.\(option.rawValue)")
                }
            } footer: {
                Text("iOS shows a brief confirmation when the app icon changes.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(HermesTheme.canvas)
        .foregroundStyle(HermesTheme.textPrimary)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selection = controller.current }
        .alert("Could not change the app icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for option: AppIconOption) -> some View {
        HStack(spacing: HermesSpacing.medium) {
            Image(option.previewAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HermesTheme.border, lineWidth: 1)
                }
            Text(option.displayName)
                .font(.body)
            Spacer()
            if option == selection {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HermesTheme.textPrimary)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, HermesSpacing.xSmall)
    }

    private func choose(_ option: AppIconOption) {
        guard controller.supportsAlternateIcons else {
            errorMessage = "This device does not support changing the app icon."
            return
        }
        Task {
            do {
                try await controller.apply(option)
                selection = option
            } catch {
                errorMessage = error.localizedDescription
                selection = controller.current
            }
        }
    }
}

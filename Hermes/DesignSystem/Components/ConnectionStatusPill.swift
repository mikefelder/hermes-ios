import SwiftUI

enum AppConnectionState: Equatable {
    case notConfigured
    case connecting
    case connected
    case offline
    case unauthorized
    case degraded
    case incompatible

    var title: String {
        switch self {
        case .notConfigured: "Not configured"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .offline: "Offline"
        case .unauthorized: "Credentials needed"
        case .degraded: "Limited"
        case .incompatible: "Incompatible"
        }
    }

    var symbol: String {
        switch self {
        case .notConfigured: "server.rack"
        case .connecting: "arrow.trianglehead.2.clockwise.rotate.90"
        case .connected: "checkmark.circle.fill"
        case .offline: "network.slash"
        case .unauthorized: "lock.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .incompatible: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .connected: HermesTheme.success
        case .connecting, .degraded: HermesTheme.warning
        case .unauthorized, .incompatible: HermesTheme.danger
        case .notConfigured, .offline: HermesTheme.textSecondary
        }
    }
}

struct ConnectionStatusPill: View {
    let state: AppConnectionState

    var body: some View {
        Label(state.title, systemImage: state.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, HermesSpacing.medium)
            .padding(.vertical, HermesSpacing.small)
            .background(HermesTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(state.color.opacity(0.4), lineWidth: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connection: \(state.title)")
    }
}

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            HermesTheme.canvas.ignoresSafeArea()
            VStack(spacing: HermesSpacing.medium) {
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .medium))
                Text("Hermes")
                    .font(.title2.weight(.semibold))
            }
            .foregroundStyle(HermesTheme.textPrimary)
            .accessibilityHidden(true)
        }
    }
}

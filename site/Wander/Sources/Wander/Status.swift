import SwiftUI

/// A booking's status, as a capsule.
public struct StatusBadge: View {
    public enum Status: String, CaseIterable, Sendable, CustomStringConvertible {
        case confirmed = "Confirmed"
        case waitlisted = "Waitlisted"
        case cancelled = "Cancelled"

        public var description: String { rawValue }

        var color: Color {
            switch self {
            case .confirmed: .green
            case .waitlisted: .orange
            case .cancelled: .red
            }
        }

        var symbol: String {
            switch self {
            case .confirmed: "checkmark.circle.fill"
            case .waitlisted: "clock.fill"
            case .cancelled: "xmark.circle.fill"
            }
        }
    }

    public var status: Status

    public init(_ status: Status) {
        self.status = status
    }

    public var body: some View {
        Label(status.rawValue, systemImage: status.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(status.color.opacity(0.15), in: .capsule)
    }
}

#Preview("Status", traits: .sizeThatFitsLayout, arguments: StatusBadge.Status.allCases) { status in
    StatusBadge(status).padding()
}

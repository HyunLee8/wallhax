import SwiftUI

struct StatsOverlay: View {
    let frameCount: Int
    let distance: Float
    let features: Int
    let trackingState: String
    let pinCount: Int
    let elapsed: TimeInterval
    let isRelayConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statRow("Frames", "\(frameCount)")
            statRow("Distance", String(format: "%.1fm", distance))
            statRow("Features", "\(features)")
            statRow("Pins", "\(pinCount)")
            statRow("Time", formatTime(elapsed))

            HStack(spacing: 4) {
                Circle()
                    .fill(trackingColor)
                    .frame(width: 6, height: 6)
                Text(trackingState)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(trackingColor)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(isRelayConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(isRelayConnected ? "relay" : "no relay")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isRelayConnected ? .green : .red)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 55, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private var trackingColor: Color {
        switch trackingState {
        case "normal":                       return .green
        case "initializing", "relocalizing": return .yellow
        default:                             return .red
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

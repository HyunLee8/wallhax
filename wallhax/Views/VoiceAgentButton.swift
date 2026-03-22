import SwiftUI
import UIKit

struct VoiceAgentButton: View {
    let accentColor: Color

    @ObservedObject private var agent = VoiceAgentManager.shared

    var body: some View {
        Circle()
            .fill(buttonColor)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: micIcon)
                    .font(.title2)
                    .foregroundColor(.white)
            )
            .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in
                if isPressing {
                    Task { try? await VoiceAgentManager.shared.start(pinColor: UIColor(accentColor)) }
                } else {
                    Task { await VoiceAgentManager.shared.stop() }
                }
            }, perform: {})
    }

    private var buttonColor: Color {
        guard agent.isActive else { return .gray.opacity(0.4) }
        return agent.isSpeaking ? accentColor : .white.opacity(0.3)
    }

    private var micIcon: String {
        agent.isActive ? "mic.fill" : "mic"
    }
}

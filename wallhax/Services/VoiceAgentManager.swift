import ElevenLabs
import UIKit
import Combine

@MainActor
final class VoiceAgentManager: ObservableObject {
    static let shared = VoiceAgentManager()

    @Published private(set) var isActive = false
    @Published private(set) var agentState: ElevenLabs.AgentState = .listening

    var isSpeaking: Bool { agentState == .speaking }

    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    private var pinColor: UIColor = .white

    private let agentId = "agent_9601kmay7vxyffjsmzvaqvr5d550"

    private init() {}

    func start(pinColor: UIColor) async throws {
        guard conversation == nil else {
            print("[VoiceAgent] start() called but conversation already exists — ignoring")
            return
        }
        print("[VoiceAgent] start() — connecting")
        self.pinColor = pinColor
        let config = ConversationConfig(
            onAgentToolRequest: { toolRequest in
                print("[VoiceAgent] agentToolRequest: \(toolRequest.toolName) type=\(toolRequest.toolType)")
            },
            onUnhandledClientToolCall: { [weak self] toolCall in
                print("[VoiceAgent] clientToolCall: \(toolCall.toolName)")
                Task { @MainActor in await self?.handleToolCall(toolCall) }
            }
        )
        do {
            conversation = try await ElevenLabs.startConversation(agentId: agentId, config: config)
            print("[VoiceAgent] connected")
            setupObservers()
        } catch {
            print("[VoiceAgent] connection failed: \(error)")
            conversation = nil
            throw error
        }
    }

    func stop() async {
        print("[VoiceAgent] stop() — conversation=\(conversation != nil)")
        cancellables.removeAll()
        await conversation?.endConversation()
        conversation = nil
        isActive = false
        agentState = .listening
        print("[VoiceAgent] stopped")
    }

    private func setupObservers() {
        guard let conversation else { return }
        conversation.$state
            .sink { [weak self] state in
                print("[VoiceAgent] state → \(state)")
                self?.isActive = state.isActive
            }
            .store(in: &cancellables)
        conversation.$agentState
            .sink { [weak self] state in
                print("[VoiceAgent] agentState → \(state)")
                self?.agentState = state
            }
            .store(in: &cancellables)
        conversation.$pendingToolCalls
            .sink { calls in
                print("[VoiceAgent] pendingToolCalls → \(calls.map(\.toolName))")
            }
            .store(in: &cancellables)
    }

    private func handleToolCall(_ toolCall: ClientToolCallEvent) async {
        do {
            let params = try toolCall.getParameters()
            let result = executeTool(name: toolCall.toolName, parameters: params)
            try await conversation?.sendToolResult(for: toolCall.toolCallId, result: result)
        } catch {
            try? await conversation?.sendToolResult(
                for: toolCall.toolCallId,
                result: ["error": error.localizedDescription],
                isError: true
            )
        }
    }

    private func executeTool(name: String, parameters: [String: Any]) -> [String: Any] {
        switch name {
        case "place_pin":
            guard let atStanding = parameters["place_where_standing"] as? Bool,
                  let pinType = parameters["pin_type"] as? String else {
                return ["error": "Missing required parameters"]
            }
            placePin(label: pinType, atStanding: atStanding)
            return ["status": "placed", "label": pinType]
        default:
            return ["error": "Unknown tool: \(name)"]
        }
    }

    private func placePin(label: String, atStanding: Bool) {
        if atStanding {
            ARState.shared.addPin(label: label)
        } else {
            ARState.shared.requestDropPin?(label, pinColor)
        }
        NetworkingManager.shared.sendPin(position: ARState.shared.position, label: label)
    }
}

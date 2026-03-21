import SwiftUI

struct CallsignEntryView: View {
    let useCase: UseCase
    let onConfirm: (String) -> Void

    @AppStorage("operatorCallsign") private var savedCallsign: String = ""
    @State private var input: String = ""
    @FocusState private var focused: Bool

    private var accent: Color { useCase.accentColor }
    private var isMilitary: Bool { useCase.id == "military" }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle radial glow behind the card
            RadialGradient(
                colors: [accent.opacity(0.12), .clear],
                center: .center,
                startRadius: 60,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Mode badge ───────────────────────────────────
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: isMilitary ? 4 : 18)
                            .fill(accent.opacity(0.15))
                            .frame(width: 64, height: 64)
                            .overlay(
                                RoundedRectangle(cornerRadius: isMilitary ? 4 : 18)
                                    .stroke(accent.opacity(0.4), lineWidth: 1)
                            )
                        Image(systemName: useCase.icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(accent)
                    }

                    Text(useCase.badge)
                        .font(.system(size: 10, weight: .black, design: isMilitary ? .monospaced : .rounded))
                        .tracking(isMilitary ? 4 : 2)
                        .foregroundColor(accent.opacity(0.7))
                }
                .padding(.bottom, 28)

                // ── Header ───────────────────────────────────────
                VStack(spacing: 6) {
                    Text(isMilitary ? "OPERATOR IDENTIFICATION" : "Who's responding?")
                        .font(.system(
                            size: isMilitary ? 13 : 22,
                            weight: isMilitary ? .black : .bold,
                            design: isMilitary ? .monospaced : .rounded
                        ))
                        .tracking(isMilitary ? 3 : 0)
                        .foregroundColor(.white)

                    Text(isMilitary ? "ENTER CALLSIGN TO PROCEED" : "Enter your name or callsign")
                        .font(.system(
                            size: isMilitary ? 10 : 14,
                            weight: isMilitary ? .regular : .medium,
                            design: isMilitary ? .monospaced : .rounded
                        ))
                        .tracking(isMilitary ? 2 : 0)
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.bottom, 28)

                // ── Input field ──────────────────────────────────
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        if isMilitary {
                            Text("ID:")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(accent.opacity(0.6))
                        }

                        TextField(isMilitary ? "CALLSIGN_" : "e.g. Alpha, Chen, Unit 4...", text: $input)
                            .font(.system(
                                size: isMilitary ? 18 : 20,
                                weight: .bold,
                                design: isMilitary ? .monospaced : .rounded
                            ))
                            .foregroundColor(isMilitary ? accent : .white)
                            .tint(accent)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(isMilitary ? .characters : .words)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { commit() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: isMilitary ? 3 : 14)
                            .stroke(focused ? accent.opacity(0.8) : accent.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: isMilitary ? 3 : 14))

                    // Character count / hint
                    HStack {
                        if isMilitary {
                            Text(input.isEmpty ? "MAX 16 CHARS" : "\(input.count)/16 CHARS")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(accent.opacity(0.4))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)

                // ── Buttons ──────────────────────────────────────
                VStack(spacing: 10) {
                    Button(action: commit) {
                        HStack(spacing: 8) {
                            if isMilitary {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .black))
                            }
                            Text(isMilitary ? "CONFIRM IDENTITY" : "Continue")
                                .font(.system(
                                    size: isMilitary ? 12 : 16,
                                    weight: isMilitary ? .black : .semibold,
                                    design: isMilitary ? .monospaced : .rounded
                                ))
                                .tracking(isMilitary ? 2 : 0)
                        }
                        .foregroundColor(input.isEmpty ? .white.opacity(0.3) : (isMilitary ? .black : .white))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isMilitary ? 14 : 16)
                        .background(
                            input.isEmpty
                                ? Color.white.opacity(0.07)
                                : accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: isMilitary ? 3 : 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: isMilitary ? 3 : 14)
                                .stroke(input.isEmpty ? Color.white.opacity(0.1) : accent, lineWidth: 1)
                        )
                    }
                    .disabled(input.isEmpty)

                    Button(action: { onConfirm(savedCallsign.isEmpty ? "UNKNOWN" : savedCallsign) }) {
                        Text(isMilitary ? "PROCEED ANONYMOUS" : "Skip")
                            .font(.system(
                                size: isMilitary ? 10 : 14,
                                weight: isMilitary ? .regular : .medium,
                                design: isMilitary ? .monospaced : .rounded
                            ))
                            .tracking(isMilitary ? 1.5 : 0)
                            .foregroundColor(.white.opacity(0.25))
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            input = savedCallsign
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                focused = true
            }
        }
    }

    private func commit() {
        guard !input.isEmpty else { return }
        let trimmed = String(input.prefix(16)).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        savedCallsign = trimmed
        onConfirm(trimmed)
    }
}

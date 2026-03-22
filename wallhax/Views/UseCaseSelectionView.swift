//
//  UseCaseSelectionView.swift
//  wallhax-ios
//

import SwiftUI

struct UseCaseSelectionView: View {
    let onSelect: (UseCase) -> Void

    @AppStorage("operatorCallsign") private var savedCallsign: String = ""
    @State private var headerVisible = false
    @State private var cardsVisible = false
    @State private var editingCallsign = false
    @State private var callsignInput: String = ""
    @FocusState private var callsignFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Radial vignette
            RadialGradient(
                colors: [.clear, .black.opacity(0.6)],
                center: .center,
                startRadius: 180,
                endRadius: 480
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Text("WallHax")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Tactical AR Mapping")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : 12)
                .padding(.top, 100)
                .padding(.bottom, 28)

                // Nameplate field
                Group {
                    if editingCallsign {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))

                            TextField("Your name or callsign", text: $callsignInput)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .tint(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.words)
                                .focused($callsignFocused)
                                .submitLabel(.done)
                                .onSubmit { commitCallsign() }

                            Button(action: commitCallsign) {
                                Text("Save")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))

                            if savedCallsign.isEmpty {
                                Text("Set your nameplate")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.3))
                            } else {
                                Text(savedCallsign)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            Button(action: {
                                callsignInput = savedCallsign
                                editingCallsign = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    callsignFocused = true
                                }
                            }) {
                                Image(systemName: savedCallsign.isEmpty ? "plus.circle" : "pencil")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .opacity(headerVisible ? 1 : 0)
                .padding(.bottom, 24)

                // Enter button
                Button(action: { onSelect(.military) }) {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("ENTER")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.60, green: 0.62, blue: 0.66).opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(red: 0.60, green: 0.62, blue: 0.66).opacity(0.5), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 20)
                .opacity(cardsVisible ? 1 : 0)
                .offset(y: cardsVisible ? 0 : 24)
                .animation(.spring(response: 0.45, dampingFraction: 0.88).delay(0.08), value: cardsVisible)

                Spacer()

                // Footer
                Text("v1.0 · Operational use only")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.bottom, 40)
                    .opacity(headerVisible ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                headerVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                cardsVisible = true
            }
        }
    }

    private func commitCallsign() {
        let trimmed = String(callsignInput.prefix(24)).trimmingCharacters(in: .whitespaces)
        savedCallsign = trimmed
        editingCallsign = false
        callsignFocused = false
    }
}


// MARK: - Use Case Card

struct UseCaseCard: View {
    let useCase: UseCase
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 18) {
                // Icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(useCase.accentColor.opacity(0.15))
                        .frame(width: 52, height: 52)

                    Image(systemName: useCase.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(useCase.accentColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(useCase.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Text(useCase.subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}


// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

//
//  UseCaseSelectionView.swift
//  wallhax-ios
//

import SwiftUI


// MARK: - Root View

struct RootView: View {
    @State private var selectedUseCase: UseCase?

    var body: some View {
        ZStack {
            if let useCase = selectedUseCase {
                ContentView(useCase: useCase, onChangeUseCase: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        selectedUseCase = nil
                    }
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.03)),
                    removal: .opacity
                ))
            } else {
                UseCaseSelectionView { useCase in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        selectedUseCase = useCase
                    }
                }
                .transition(.opacity)
            }
        }
    }
}


// MARK: - Selection Screen

struct UseCaseSelectionView: View {
    let onSelect: (UseCase) -> Void

    @State private var headerVisible = false
    @State private var cardsVisible = false

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

                    Text("Select your operational mode")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : 12)
                .padding(.top, 100)
                .padding(.bottom, 52)

                // Cards
                VStack(spacing: 14) {
                    ForEach(Array(UseCase.allCases.enumerated()), id: \.offset) { index, useCase in
                        UseCaseCard(useCase: useCase) {
                            onSelect(useCase)
                        }
                        .opacity(cardsVisible ? 1 : 0)
                        .offset(y: cardsVisible ? 0 : 24)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.88)
                                .delay(Double(index) * 0.08),
                            value: cardsVisible
                        )
                    }
                }
                .padding(.horizontal, 20)

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

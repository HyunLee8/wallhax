//
//  RootView.swift
//  wallhax
//
//  Created by Ken Zhou on 3/21/26.
//

import SwiftUI

struct RootView: View {
    @AppStorage("operatorCallsign") private var savedCallsign: String = ""
    @State private var selectedUseCase: UseCase?

    var body: some View {
        ZStack {
            if let useCase = selectedUseCase {
                // ── Operational view ─────────────────────────────
                Group {
                    if useCase.id == "military" {
                        MilitaryOperationsView(useCase: useCase, callsign: savedCallsign, onExit: exit)
                    } else {
                        ContentView(useCase: useCase, callsign: savedCallsign, onExit: exit)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.03)),
                    removal: .opacity
                ))

            } else {
                // ── Mode selection ───────────────────────────────
                UseCaseSelectionView { useCase in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        selectedUseCase = useCase
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func exit() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            selectedUseCase = nil
        }
    }
}

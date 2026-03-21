//
//  RootView.swift
//  wallhax
//
//  Created by Ken Zhou on 3/21/26.
//

import SwiftUI

struct RootView: View {
    @State private var pendingUseCase: UseCase?   // mode chosen, awaiting callsign
    @State private var selectedUseCase: UseCase?  // mode + callsign confirmed
    @State private var callsign: String = ""

    var body: some View {
        ZStack {
            if let useCase = selectedUseCase {
                // ── Operational view ─────────────────────────────
                Group {
                    if useCase.id == "military" {
                        MilitaryOperationsView(useCase: useCase, callsign: callsign, onExit: exit)
                    } else {
                        ContentView(useCase: useCase, callsign: callsign, onExit: exit)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.03)),
                    removal: .opacity
                ))

            } else if let useCase = pendingUseCase {
                // ── Callsign entry ───────────────────────────────
                CallsignEntryView(useCase: useCase) { name in
                    callsign = name
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        pendingUseCase = nil
                        selectedUseCase = useCase
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))

            } else {
                // ── Mode selection ───────────────────────────────
                UseCaseSelectionView { useCase in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        pendingUseCase = useCase
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func exit() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            selectedUseCase = nil
            pendingUseCase = nil
        }
    }
}

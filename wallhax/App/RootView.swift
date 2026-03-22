//
//  RootView.swift
//  wallhax
//
//  Created by Ken Zhou on 3/21/26.
//

import SwiftUI

private enum AppStage {
    case selection
    case operational(UseCase)
}

struct RootView: View {
    @AppStorage("operatorCallsign") private var savedCallsign: String = ""
    @State private var stage: AppStage = .selection

    var body: some View {
        ZStack {
            switch stage {
            case .selection:
                UseCaseSelectionView { useCase in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        stage = .operational(useCase)
                    }
                }
                .transition(.opacity)

            case .operational(let useCase):
                MilitaryOperationsView(useCase: useCase, callsign: savedCallsign, onExit: exit)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.03)),
                    removal: .opacity
                ))
            }
        }
    }

    private func exit() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            stage = .selection
        }
    }
}

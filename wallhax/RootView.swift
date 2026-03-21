//
//  RootView.swift
//  wallhax
//
//  Created by Ken Zhou on 3/21/26.
//

import SwiftUI

struct RootView: View {
    @State private var selectedUseCase: UseCase?

    var body: some View {
        ZStack {
            if let useCase = selectedUseCase {
                ContentView(useCase: useCase, onExit: {
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

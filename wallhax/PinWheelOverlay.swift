import ARKit
import Combine
import RealityKit
import SwiftUI

struct PinWheelOverlay: View {
    let labels: [(label: String, icon: String)]
    let accentColor: Color
    let selectedIndex: Int?

    private let wheelRadius: CGFloat = 112

    private var center: CGPoint {
        let s = UIScreen.main.bounds
        return CGPoint(x: s.width / 2, y: s.height * 0.42)
    }

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            // Wheel ring
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: wheelRadius * 2, height: wheelRadius * 2)
                .position(center)

            // Items
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, item in
                let angle = -Double.pi / 2 + Double(idx) * (2 * Double.pi / Double(labels.count))
                let itemPos = CGPoint(
                    x: center.x + wheelRadius * CGFloat(cos(angle)),
                    y: center.y + wheelRadius * CGFloat(sin(angle))
                )
                let selected = selectedIndex == idx

                VStack(spacing: 5) {
                    Image(systemName: item.icon)
                        .font(.system(size: selected ? 20 : 16, weight: .semibold))
                        .foregroundColor(selected ? .white : .white.opacity(0.65))
                    Text(item.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(selected ? .white : .white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(width: 70, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? accentColor.opacity(0.88) : Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selected ? accentColor : Color.white.opacity(0.09), lineWidth: 1)
                        )
                )
                .scaleEffect(selected ? 1.13 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.65), value: selected)
                .position(itemPos)
            }

            // Center indicator
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 46, height: 46)
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                if let idx = selectedIndex {
                    Image(systemName: labels[idx].icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .animation(.spring(response: 0.2), value: selectedIndex)
            .position(center)
        }
    }
}

import ARKit
import Combine
import RealityKit
import SwiftUI

struct PinWheelOverlay: View {
    let labels: [(label: String, icon: String)]
    let accentColor: Color
    let selectedIndex: Int?
    let useCaseId: String

    private let wheelRadius: CGFloat = 112

    private var isMilitary: Bool    { useCaseId == "military" }
    private var isFirefighter: Bool { useCaseId == "firefighter" }

    private var itemWidth: CGFloat  { isMilitary ? 72 : isFirefighter ? 62 : 78 }
    private var itemHeight: CGFloat { isMilitary ? 50 : isFirefighter ? 62 : 44 }

    private var center: CGPoint {
        let s = UIScreen.main.bounds
        return CGPoint(x: s.width / 2, y: s.height * 0.42)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(isMilitary ? 0.60 : 0.40)
                .ignoresSafeArea()

            // Military: radial connector lines
            if isMilitary {
                Canvas { context, _ in
                    for idx in 0..<labels.count {
                        let angle = -Double.pi / 2 + Double(idx) * (2 * .pi / Double(labels.count))
                        let itemPos = CGPoint(
                            x: center.x + wheelRadius * CGFloat(cos(angle)),
                            y: center.y + wheelRadius * CGFloat(sin(angle))
                        )
                        let isSelected = selectedIndex == idx
                        var line = Path()
                        line.move(to: center)
                        line.addLine(to: itemPos)
                        context.stroke(line,
                                       with: .color(accentColor.opacity(isSelected ? 0.55 : 0.18)),
                                       lineWidth: isSelected ? 1.5 : 0.5)
                    }
                }
                .allowsHitTesting(false)
            }

            // Wheel ring
            if !isFirefighter {
                Circle()
                    .stroke(accentColor.opacity(isMilitary ? 0.22 : 0.08), lineWidth: isMilitary ? 0.5 : 1)
                    .frame(width: wheelRadius * 2, height: wheelRadius * 2)
                    .position(center)
            }

            // Items
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, item in
                let angle = -Double.pi / 2 + Double(idx) * (2 * .pi / Double(labels.count))
                let itemPos = CGPoint(
                    x: center.x + wheelRadius * CGFloat(cos(angle)),
                    y: center.y + wheelRadius * CGFloat(sin(angle))
                )
                let selected = selectedIndex == idx

                pinItem(item: item, selected: selected)
                    .frame(width: itemWidth, height: itemHeight)
                    .scaleEffect(selected ? 1.12 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.65), value: selected)
                    .position(itemPos)
            }

            // Center indicator
            centerIndicator
                .animation(.spring(response: 0.2), value: selectedIndex)
                .position(center)
        }
        .drawingGroup()
    }

    // MARK: - Per-mode item

    @ViewBuilder
    private func pinItem(item: (label: String, icon: String), selected: Bool) -> some View {
        if isMilitary {
            // Sharp tactical badge
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: selected ? 17 : 13, weight: .semibold))
                    .foregroundColor(selected ? .black : accentColor.opacity(0.85))
                Text(item.label.uppercased())
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(selected ? .black.opacity(0.85) : accentColor.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(selected ? accentColor : accentColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(selected ? accentColor : accentColor.opacity(0.40), lineWidth: selected ? 1.5 : 0.5)
                    )
            )

        } else if isFirefighter {
            // Bold circular badge
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: selected ? 22 : 17, weight: .bold))
                    .foregroundColor(selected ? .white : .white.opacity(0.70))
                Text(item.label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(selected ? .white : .white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .background(
                Circle()
                    .fill(selected ? accentColor.opacity(0.92) : Color.white.opacity(0.10))
                    .overlay(Circle().stroke(selected ? accentColor : Color.white.opacity(0.18), lineWidth: selected ? 2 : 1))
            )

        } else {
            // SAR: horizontal capsule
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: selected ? 15 : 12, weight: .semibold))
                    .foregroundColor(selected ? .white : .white.opacity(0.65))
                Text(item.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(selected ? .white : .white.opacity(0.60))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(selected ? accentColor.opacity(0.90) : Color.white.opacity(0.08))
                    .overlay(Capsule().stroke(selected ? accentColor : Color.white.opacity(0.13), lineWidth: 1))
            )
        }
    }

    // MARK: - Center indicator

    @ViewBuilder
    private var centerIndicator: some View {
        ZStack {
            if isMilitary {
                // Crosshair ring
                Circle()
                    .stroke(accentColor.opacity(0.35), lineWidth: 0.5)
                    .frame(width: 46, height: 46)
                // Crosshair ticks
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 0.5, height: 14)
                    .offset(y: -16)
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 0.5, height: 14)
                    .offset(y: 16)
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 14, height: 0.5)
                    .offset(x: -16)
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 14, height: 0.5)
                    .offset(x: 16)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(accentColor.opacity(0.22), lineWidth: 1))
            }

            if let idx = selectedIndex {
                Image(systemName: labels[idx].icon)
                    .font(.system(size: isMilitary ? 15 : 19, weight: .semibold))
                    .foregroundColor(isMilitary ? accentColor : .white)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: isMilitary ? "scope" : isFirefighter ? "flame.fill" : "magnifyingglass")
                    .font(.system(size: isMilitary ? 13 : 17, weight: isMilitary ? .light : .semibold))
                    .foregroundColor(accentColor.opacity(0.45))
            }
        }
    }
}

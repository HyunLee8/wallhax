//
//  MapViews.swift
//  wallhax-ios
//

import SwiftUI
import ARKit


// MARK: - Peer Colors

private let peerPalette: [Color] = [
    Color(red: 0.91, green: 0.40, blue: 0.35),
    Color(red: 0.36, green: 0.56, blue: 0.84),
    Color(red: 0.67, green: 0.28, blue: 0.74),
    Color(red: 0.15, green: 0.78, blue: 0.85),
    Color(red: 1.0,  green: 0.44, blue: 0.26),
    Color(red: 0.55, green: 0.76, blue: 0.29),
]

private func peerColor(for peerId: String) -> Color {
    peerPalette[abs(peerId.hashValue) % peerPalette.count]
}


// MARK: - Map Canvas

struct MapCanvas: View {
    let trajectory: [SIMD2<Float>]
    let currentPos: SIMD2<Float>
    let heading: Float
    let pins: [MapPin]
    let peers: [String: PeerMapState]
    let scale: CGFloat
    let offset: CGSize
    let centerOnUser: Bool
    let showLabels: Bool
    let accentColor: Color

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2 + offset.width,
                                 y: canvasSize.height / 2 + offset.height)

            let anchorX = centerOnUser ? currentPos.x : 0
            let anchorY = centerOnUser ? currentPos.y : 0

            let (anchorXFinal, anchorYFinal): (Float, Float) = {
                if !centerOnUser && !trajectory.isEmpty {
                    let minX = trajectory.map { $0.x }.min() ?? 0
                    let maxX = trajectory.map { $0.x }.max() ?? 0
                    let minY = trajectory.map { $0.y }.min() ?? 0
                    let maxY = trajectory.map { $0.y }.max() ?? 0
                    return ((minX + maxX) / 2, (minY + maxY) / 2)
                }
                return (anchorX, anchorY)
            }()

            func toScreen(_ pt: SIMD2<Float>) -> CGPoint {
                let x = center.x + CGFloat(pt.x - anchorXFinal) * scale
                let y = center.y + CGFloat(pt.y - anchorYFinal) * scale
                return CGPoint(x: x, y: y)
            }

            func drawTriangle(at cp: CGPoint, heading h: Float, size triSize: CGFloat, color: Color) {
                var tri = Path()
                let tipX = cp.x + sin(CGFloat(h)) * triSize
                let tipY = cp.y + cos(CGFloat(h)) * triSize
                let leftX = cp.x + sin(CGFloat(h) + 2.4) * triSize * 0.6
                let leftY = cp.y + cos(CGFloat(h) + 2.4) * triSize * 0.6
                let rightX = cp.x + sin(CGFloat(h) - 2.4) * triSize * 0.6
                let rightY = cp.y + cos(CGFloat(h) - 2.4) * triSize * 0.6
                tri.move(to: CGPoint(x: tipX, y: tipY))
                tri.addLine(to: CGPoint(x: leftX, y: leftY))
                tri.addLine(to: CGPoint(x: rightX, y: rightY))
                tri.closeSubpath()
                context.fill(tri, with: .color(color))
            }

            // Grid
            let gridSpacing = scale * 1.0
            if gridSpacing > 8 {
                let startX = center.x.truncatingRemainder(dividingBy: gridSpacing)
                let startY = center.y.truncatingRemainder(dividingBy: gridSpacing)
                for i in 0..<Int(canvasSize.width / gridSpacing) + 2 {
                    let x = startX + CGFloat(i) * gridSpacing
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }
                for i in 0..<Int(canvasSize.height / gridSpacing) + 2 {
                    let y = startY + CGFloat(i) * gridSpacing
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }
            }

            // Peer trajectories and positions
            let peerTriSize: CGFloat = showLabels ? 10 : 7
            for (peerId, peer) in peers {
                let color = peerColor(for: peerId)
                let traj = peer.trajectory
                if traj.count >= 2 {
                    var path = Path()
                    for (i, pt) in traj.enumerated() {
                        let sp = toScreen(pt)
                        if i == 0 { path.move(to: sp) }
                        else { path.addLine(to: sp) }
                    }
                    context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: showLabels ? 2.0 : 1.2)
                }
                if let lastPt = traj.last {
                    drawTriangle(at: toScreen(lastPt), heading: peer.heading, size: peerTriSize, color: color)
                }
            }

            // Local trajectory
            if trajectory.count >= 2 {
                var path = Path()
                for (i, pt) in trajectory.enumerated() {
                    let sp = toScreen(pt)
                    if i == 0 { path.move(to: sp) }
                    else { path.addLine(to: sp) }
                }
                context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: showLabels ? 2.5 : 1.5)
            }

            // Pins
            let pinSize: CGFloat = showLabels ? 10 : 6
            for pin in pins {
                let sp = toScreen(pin.position2D)
                let pinRect = CGRect(x: sp.x - pinSize/2, y: sp.y - pinSize/2, width: pinSize, height: pinSize)
                context.fill(Path(ellipseIn: pinRect), with: .color(accentColor))
                context.stroke(Path(ellipseIn: pinRect), with: .color(.white), lineWidth: 1.5)

                if showLabels {
                    let text = Text(pin.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    context.draw(text, at: CGPoint(x: sp.x, y: sp.y - pinSize - 8))
                }
            }

            // Local position triangle
            let triSize: CGFloat = showLabels ? 12 : 8
            let cp = toScreen(SIMD2<Float>(currentPos.x, currentPos.y))
            drawTriangle(at: cp, heading: heading, size: triSize, color: .white)
        }
    }
}


// MARK: - Minimap

struct MinimapView: View {
    let trajectory: [SIMD2<Float>]
    let currentPos: SIMD2<Float>
    let heading: Float
    let pins: [MapPin]
    let peers: [String: PeerMapState]
    let accentColor: Color
    let onTap: () -> Void
    let size: CGFloat = 140

    var body: some View {
        MapCanvas(
            trajectory: trajectory,
            currentPos: currentPos,
            heading: heading,
            pins: pins,
            peers: peers,
            scale: 140.0 / 2.0 / 8.0,
            offset: .zero,
            centerOnUser: true,
            showLabels: false,
            accentColor: accentColor
        )
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .padding(6),
            alignment: .topTrailing
        )
        .onTapGesture {
            onTap()
        }
    }
}


// MARK: - Full Map

struct FullMapView: View {
    let trajectory: [SIMD2<Float>]
    let currentPos: SIMD2<Float>
    let heading: Float
    let pins: [MapPin]
    let peers: [String: PeerMapState]
    let accentColor: Color
    let onClose: () -> Void

    @State private var scale: CGFloat = 15
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 15
    @State private var centerOnUser = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .edgesIgnoringSafeArea(.all)

            MapCanvas(
                trajectory: trajectory,
                currentPos: currentPos,
                heading: heading,
                pins: pins,
                peers: peers,
                scale: scale,
                offset: CGSize(width: offset.width + dragOffset.width,
                               height: offset.height + dragOffset.height),
                centerOnUser: centerOnUser,
                showLabels: true,
                accentColor: accentColor
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                        centerOnUser = false
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                        scale = min(max(scale, 3), 80)
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
            .edgesIgnoringSafeArea(.all)

            // Controls overlay
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "map")
                            .foregroundColor(accentColor)
                        Text("MAP")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(pins.count) pins")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            centerOnUser = true
                            offset = .zero
                            dragOffset = .zero
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13))
                            Text("Center")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(centerOnUser ? accentColor : .white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.2)) {
                                scale = min(scale * 1.5, 80)
                                lastScale = scale
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 40, height: 36)
                        }

                        Divider()
                            .frame(height: 20)
                            .background(Color.white.opacity(0.15))

                        Button(action: {
                            withAnimation(.spring(response: 0.2)) {
                                scale = max(scale / 1.5, 3)
                                lastScale = scale
                            }
                        }) {
                            Image(systemName: "minus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 40, height: 36)
                        }
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(String(format: "%.0fm/div", 1.0))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
    }
}

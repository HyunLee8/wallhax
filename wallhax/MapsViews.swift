//
//  MapViews.swift
//  wallhax-ios
//

import SwiftUI
import UIKit
import SceneKit
import ARKit
import SCNLine

let FLOOR_OPACITY = 0.30
let WALL_OPACITY = 0.50
let FLOOR_THICKNESS = 0.10
let WALL_THICKNESS = 0.10
let TRAIL_THICKNESS: CGFloat = 0.10

// MARK: - Peer Colors

private let peerPaletteUI: [UIColor] = [
    UIColor(red: 0.91, green: 0.40, blue: 0.35, alpha: 1),
    UIColor(red: 0.36, green: 0.56, blue: 0.84, alpha: 1),
    UIColor(red: 0.67, green: 0.28, blue: 0.74, alpha: 1),
    UIColor(red: 0.15, green: 0.78, blue: 0.85, alpha: 1),
    UIColor(red: 1.0,  green: 0.44, blue: 0.26, alpha: 1),
    UIColor(red: 0.55, green: 0.76, blue: 0.29, alpha: 1),
]

private func peerColorUI(for peerId: String) -> UIColor {
    peerPaletteUI[abs(peerId.hashValue) % peerPaletteUI.count]
}

private func peerColor(for peerId: String) -> Color {
    Color(uiColor: peerColorUI(for: peerId))
}


// MARK: - Gesture Capture (provides pinch center for correct zoom-to-cursor)

private struct GestureCapture: UIViewRepresentable {
    let onPinch: (_ delta: CGFloat, _ center: CGPoint) -> Void
    let onPan: (_ translation: CGSize) -> Void
    let onPanEnd: (_ translation: CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch))
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject {
        var parent: GestureCapture
        private var lastPinchScale: CGFloat = 1
        init(_ parent: GestureCapture) { self.parent = parent }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: lastPinchScale = 1
            case .changed:
                let delta = g.scale / lastPinchScale
                lastPinchScale = g.scale
                parent.onPinch(delta, g.location(in: g.view))
            default: break
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            let size = CGSize(width: t.x, height: t.y)
            switch g.state {
            case .changed: parent.onPan(size)
            case .ended, .cancelled: parent.onPanEnd(size)
            default: break
            }
        }
    }
}


// MARK: - Map Canvas

struct MapCanvas: View {
    let trajectory: [simd_float4x4]
    let currentPos: SIMD2<Float>
    let heading: Float
    let pins: [MapPin]
    let peers: [String: PeerMapState]
    let walls: [Wall3D]
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
                    let minX = trajectory.map { $0.columns.3.x }.min() ?? 0
                    let maxX = trajectory.map { $0.columns.3.x }.max() ?? 0
                    let minY = trajectory.map { $0.columns.3.z }.min() ?? 0
                    let maxY = trajectory.map { $0.columns.3.z }.max() ?? 0
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

            // Walls (vertical planes)
            for wall in walls {
                let half = wall.width / 2
                let start = SIMD2<Float>(wall.center.x - wall.xDirXZ.x * half,
                                         wall.center.z - wall.xDirXZ.y * half)
                let end   = SIMD2<Float>(wall.center.x + wall.xDirXZ.x * half,
                                         wall.center.z + wall.xDirXZ.y * half)
                var path = Path()
                path.move(to: toScreen(start))
                path.addLine(to: toScreen(end))
                context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: showLabels ? 3 : 2)
            }

            // Peer trajectories and positions
            let peerTriSize: CGFloat = showLabels ? 10 : 7
            for (peerId, peer) in peers {
                let color = peerColor(for: peerId)
                let traj = peer.trajectory
                if traj.count >= 2 {
                    var path = Path()
                    for (i, t) in traj.enumerated() {
                        let sp = toScreen(SIMD2(t.columns.3.x, t.columns.3.z))
                        if i == 0 { path.move(to: sp) }
                        else { path.addLine(to: sp) }
                    }
                    context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: showLabels ? 2.0 : 1.2)
                }
                if let last = traj.last {
                    drawTriangle(at: toScreen(SIMD2(last.columns.3.x, last.columns.3.z)),
                                 heading: peer.heading, size: peerTriSize, color: color)
                }
            }

            // Local trajectory
            if trajectory.count >= 2 {
                var path = Path()
                for (i, t) in trajectory.enumerated() {
                    let sp = toScreen(SIMD2(t.columns.3.x, t.columns.3.z))
                    if i == 0 { path.move(to: sp) }
                    else { path.addLine(to: sp) }
                }
                context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: showLabels ? 2.5 : 1.5)
            }

            // Pins
            let pinIconSize: CGFloat = showLabels ? 20 : 11
            for pin in pins {
                let sp = toScreen(pin.position2D)

                let pinSym = Text(Image(systemName: "mappin.fill"))
                    .font(.system(size: pinIconSize))
                    .foregroundColor(accentColor)
                context.draw(pinSym, at: sp, anchor: .bottom)

                if showLabels {
                    let labelY = sp.y - pinIconSize - 14
                    let labelWidth = CGFloat(max(pin.label.count * 7, 44))
                    let pill = Path(roundedRect: CGRect(x: sp.x - labelWidth / 2,
                                                        y: labelY - 9,
                                                        width: labelWidth,
                                                        height: 17),
                                    cornerRadius: 5)
                    context.fill(pill, with: .color(.black.opacity(0.68)))
                    context.stroke(pill, with: .color(.white.opacity(0.18)), lineWidth: 0.5)

                    let labelText = Text(pin.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    context.draw(labelText, at: CGPoint(x: sp.x, y: labelY))
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
    let trajectory: [simd_float4x4]
    let currentPos: SIMD2<Float>
    let heading: Float
    let pins: [MapPin]
    let peers: [String: PeerMapState]
    let walls: [Wall3D]
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
            walls: walls,
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
    let trajectory: [simd_float4x4]
    let currentPos: SIMD2<Float>
    let heading: Float
    let pins: [MapPin]
    let peers: [String: PeerMapState]
    let walls: [Wall3D]
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

            GeometryReader { geo in
                MapCanvas(
                    trajectory: trajectory,
                    currentPos: currentPos,
                    heading: heading,
                    pins: pins,
                    peers: peers,
                    walls: walls,
                    scale: scale,
                    offset: CGSize(width: offset.width + dragOffset.width,
                                   height: offset.height + dragOffset.height),
                    centerOnUser: centerOnUser,
                    showLabels: true,
                    accentColor: accentColor
                )
                .overlay(
                    GestureCapture(
                        onPinch: { delta, center in
                            let newScale = min(max(scale * delta, 3.0), 80.0)
                            let ratio = newScale / scale
                            offset.width  = (center.x - geo.size.width  / 2) * (1 - ratio) + offset.width  * ratio
                            offset.height = (center.y - geo.size.height / 2) * (1 - ratio) + offset.height * ratio
                            scale = newScale
                            lastScale = newScale
                            centerOnUser = false
                        },
                        onPan: { t in dragOffset = t; centerOnUser = false },
                        onPanEnd: { t in
                            offset.width  += t.width
                            offset.height += t.height
                            dragOffset = .zero
                        }
                    )
                )
            }
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


// MARK: - 3D Helpers

private func makePointerNode(at pos: SIMD3<Float>, heading: Float, color: UIColor) -> SCNNode {
    let cone = SCNCone(topRadius: 0, bottomRadius: 0.22, height: 0.55)
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.emission.contents = color.withAlphaComponent(0.35)
    cone.materials = [mat]
    let node = SCNNode(geometry: cone)
    node.position = SCNVector3(pos.x, pos.y + 0.28, pos.z)
    node.eulerAngles = SCNVector3(Float.pi / 2, heading, 0)
    return node
}

// MARK: - 3D Map

private final class Map3DCoordinator: NSObject {
    let scnView = SCNView()
    let scene   = SCNScene()

    private let wallsNode  = SCNNode()
    private let floorsNode = SCNNode()
    private let pathNode   = SCNNode()
    private let selfNode   = SCNNode()
    private let peersNode  = SCNNode()
    private let pinsNode   = SCNNode()

    private var lastWallCount         = -1
    private var lastFloorCount        = -1
    private var lastTrajectoryCount   = -1
    private var lastPeerTrajCounts    = [String: Int]()
    private var lastPinCount          = -1
    private var didFitCamera          = false

    override init() {
        super.init()
        for node in [floorsNode, wallsNode, pathNode, selfNode, peersNode, pinsNode] {
            scene.rootNode.addChildNode(node)
        }
    }

    func update(trajectory: [simd_float4x4], currentPos: SIMD3<Float>, heading: Float,
                walls: [Wall3D], floors: [HFloor], peers: [String: PeerMapState],
                pins: [MapPin], accentColor: UIColor) {
        if walls.count != lastWallCount {
            rebuildWalls(walls); lastWallCount = walls.count
        }
        if floors.count != lastFloorCount {
            rebuildFloors(floors); lastFloorCount = floors.count
        }
        if trajectory.count != lastTrajectoryCount {
            rebuildPath(trajectory); lastTrajectoryCount = trajectory.count
        }
        let needsPeerRebuild = peers.contains { id, state in
            lastPeerTrajCounts[id] != state.trajectory.count
        } || lastPeerTrajCounts.keys.contains { !peers.keys.contains($0) }
        if needsPeerRebuild {
            rebuildPeers(peers)
            lastPeerTrajCounts = peers.mapValues { $0.trajectory.count }
        }
        if pins.count != lastPinCount {
            rebuildPins(pins, accentColor: accentColor); lastPinCount = pins.count
        }
        rebuildSelf(currentPos: currentPos, heading: heading)

        if !didFitCamera && !trajectory.isEmpty {
            fitCamera(trajectory: trajectory, walls3D: walls)
            didFitCamera = true
        }
    }

    private func rebuildWalls(_ walls: [Wall3D]) {
        wallsNode.childNodes.forEach { $0.removeFromParentNode() }
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.85, alpha: WALL_OPACITY)
        mat.isDoubleSided = true

        for wall in walls {
            guard wall.width > 0.1 && wall.height > 0.05 else { continue }
            let box = SCNBox(width: CGFloat(wall.width), height: CGFloat(wall.height),
                             length: WALL_THICKNESS, chamferRadius: 0.02)
            box.materials = [mat]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(wall.center.x, wall.center.y, wall.center.z)
            node.eulerAngles.y = atan2(wall.xDirXZ.y, wall.xDirXZ.x)
            wallsNode.addChildNode(node)
        }
    }

    private func rebuildFloors(_ floors: [HFloor]) {
        floorsNode.childNodes.forEach { $0.removeFromParentNode() }
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.85, alpha: FLOOR_OPACITY)
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false

        for floor in floors {
            let box = SCNBox(width: CGFloat(floor.widthX), height: FLOOR_THICKNESS,
                             length: CGFloat(floor.depthZ), chamferRadius: 0)
            box.materials = [mat]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(floor.center.x, floor.center.y, floor.center.z)
            node.eulerAngles.y = atan2(floor.xDirXZ.y, floor.xDirXZ.x)
            floorsNode.addChildNode(node)
        }
    }

    /// Builds a deduplicated SCNLineNode from a transform trajectory using full XYZ positions.
    /// SCNLine's normalize() produces NaN for near-zero segments, so consecutive points
    /// closer than 1 cm are skipped before the geometry is created.
    private func makeTrailNode(trajectory: [simd_float4x4], color: UIColor) -> SCNLineNode? {
        var points: [SCNVector3] = []
        for t in trajectory {
            let v = SCNVector3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            if let last = points.last {
                let dx = v.x - last.x, dy = v.y - last.y, dz = v.z - last.z
                guard dx * dx + dy * dy + dz * dz > 0.0001 else { continue }
            }
            points.append(v)
        }
        guard points.count >= 2 else { return nil }

        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .constant
        let lineNode = SCNLineNode(with: points, radius: Float(TRAIL_THICKNESS) / 2, edges: 12, maxTurning: 4)
        lineNode.lineMaterials = [mat]
        return lineNode
    }

    private func rebuildPath(_ trajectory: [simd_float4x4]) {
        pathNode.childNodes.forEach { $0.removeFromParentNode() }
        if let node = makeTrailNode(trajectory: trajectory, color: .white.withAlphaComponent(0.8)) {
            pathNode.addChildNode(node)
        }
    }

    private func rebuildSelf(currentPos: SIMD3<Float>, heading: Float) {
        selfNode.childNodes.forEach { $0.removeFromParentNode() }
        selfNode.addChildNode(makePointerNode(at: currentPos, heading: heading, color: .white))
    }

    private func rebuildPeers(_ peers: [String: PeerMapState]) {
        peersNode.childNodes.forEach { $0.removeFromParentNode() }
        for (peerId, state) in peers {
            let color = peerColorUI(for: peerId)

            // Trail
            if let node = makeTrailNode(trajectory: state.trajectory, color: color.withAlphaComponent(0.6)) {
                peersNode.addChildNode(node)
            }

            // Pointer cone
            if let last = state.trajectory.last {
                let pos = SIMD3<Float>(last.columns.3.x, last.columns.3.y, last.columns.3.z)
                peersNode.addChildNode(makePointerNode(at: pos, heading: state.heading, color: color))
            }
        }
    }

    private func rebuildPins(_ pins: [MapPin], accentColor: UIColor) {
        pinsNode.childNodes.forEach { $0.removeFromParentNode() }
        for pin in pins {
            let sphere = SCNSphere(radius: 0.12)
            let mat = SCNMaterial()
            mat.diffuse.contents = accentColor
            mat.emission.contents = accentColor.withAlphaComponent(0.4)
            sphere.materials = [mat]
            let head = SCNNode(geometry: sphere)
            head.position = SCNVector3(pin.position.x, max(pin.position.y + 0.8, 0.8), pin.position.z)

            let stem = SCNCylinder(radius: 0.025, height: 0.75)
            let stemMat = SCNMaterial()
            stemMat.diffuse.contents = accentColor.withAlphaComponent(0.5)
            stem.materials = [stemMat]
            let stemNode = SCNNode(geometry: stem)
            stemNode.position = SCNVector3(pin.position.x, max(pin.position.y + 0.42, 0.42), pin.position.z)
            pinsNode.addChildNode(head)
            pinsNode.addChildNode(stemNode)
        }
    }

    func fitCamera(trajectory: [simd_float4x4], walls3D: [Wall3D]) {
        guard let camNode = scnView.pointOfView, !trajectory.isEmpty else { return }

        var allX = trajectory.map { $0.columns.3.x }
        var allZ = trajectory.map { $0.columns.3.z }
        allX += walls3D.map { $0.center.x }
        allZ += walls3D.map { $0.center.z }

        let minX = allX.min()!, maxX = allX.max()!
        let minZ = allZ.min()!, maxZ = allZ.max()!
        let cx = (minX + maxX) / 2
        let cz = (minZ + maxZ) / 2
        let span = max(maxX - minX, maxZ - minZ, 4)
        let dist = span * 0.7 + 6

        let target = SCNVector3(cx, 0, cz)
        scnView.defaultCameraController.target = target

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        camNode.position = SCNVector3(cx, dist, cz + dist * 0.65)
        camNode.look(at: target)
        SCNTransaction.commit()
    }
}

private struct Map3DContainer: UIViewRepresentable {
    let trajectory: [simd_float4x4]
    let currentPos: SIMD3<Float>
    let heading: Float
    let walls: [Wall3D]
    let floors: [HFloor]
    let peers: [String: PeerMapState]
    let pins: [MapPin]
    let accentColor: Color
    @Binding var shouldCenter: Bool

    func makeCoordinator() -> Map3DCoordinator { Map3DCoordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = context.coordinator.scnView
        v.scene = context.coordinator.scene
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.backgroundColor = UIColor(white: 0.05, alpha: 1)
        v.autoenablesDefaultLighting = true
        v.antialiasingMode = .multisampling4X

        // Seed a camera so pointOfView is non-nil before first data arrives
        let cam = SCNCamera()
        cam.zNear = 0.1
        cam.zFar = 500
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 20, 15)
        camNode.look(at: SCNVector3(0, 0, 0))
        context.coordinator.scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.update(
            trajectory: trajectory, currentPos: currentPos, heading: heading,
            walls: walls, floors: floors, peers: peers, pins: pins,
            accentColor: UIColor(accentColor)
        )
        if shouldCenter {
            context.coordinator.fitCamera(trajectory: trajectory, walls3D: walls)
            DispatchQueue.main.async { shouldCenter = false }
        }
    }
}

struct FullMap3DView: View {
    let trajectory: [simd_float4x4]
    let currentPos: SIMD3<Float>
    let heading: Float
    let pins: [MapPin]
    let peers: [String: PeerMapState]
    let walls: [Wall3D]
    let floors: [HFloor]
    let accentColor: Color
    let onClose: () -> Void

    @State private var shouldCenter = false

    var body: some View {
        ZStack {
            Map3DContainer(trajectory: trajectory, currentPos: currentPos, heading: heading,
                           walls: walls, floors: floors, peers: peers, pins: pins,
                           accentColor: accentColor, shouldCenter: $shouldCenter)
                .edgesIgnoringSafeArea(.all)

            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "cube")
                            .foregroundColor(accentColor)
                        Text("3D MAP")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(pins.count) pins · \(walls.count) walls")
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

                HStack {
                    Button(action: { shouldCenter = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13))
                            Text("Fit Scene")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
    }
}

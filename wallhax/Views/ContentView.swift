import SwiftUI
import Combine
import RealityKit
import ARKit
import SceneKit

// MARK: - Main Content View

struct ContentView: View {
    let useCase: UseCase
    let callsign: String
    let onExit: () -> Void

    @StateObject private var arState = ARState.shared
    @AppStorage("lidarEnabled") private var lidarEnabled = true
    @State private var lidarLoading = false
    @State private var isRecording = false
    @State private var hasRecording = false
    @State private var frameCount = 0
    @State private var isSending = false
    @State private var sendStatus = ""
    @State private var showPinWheel = false
    @State private var selectedPinIndex: Int? = nil
    @State private var showFullMap = false
    @State private var recordingStartTime: Date?
    @State private var elapsed: TimeInterval = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var accentColor: Color { useCase.accentColor }

    var body: some View {
        ZStack {
            ARViewContainer(isRecording: $isRecording, lidarEnabled: $lidarEnabled, callsign: callsign)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)

            if arState.originLocked {
            Group {
            // ── Crosshair ────────────────────────────────────────
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 18, height: 1.5)
                Rectangle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 1.5, height: 18)
                Circle()
                    .fill(Color.white)
                    .frame(width: 3, height: 3)
            }
            .shadow(color: .black.opacity(0.6), radius: 2)
            .allowsHitTesting(false)

            // ── Top area + bottom controls ───────────────────────
            VStack {
                HStack(alignment: .top, spacing: 10) {
                    // Back button + minimap stacked
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button(action: {
                                ARState.shared.reset()
                                onExit()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 10, weight: .bold))
                                    Circle()
                                        .fill(accentColor)
                                        .frame(width: 5, height: 5)
                                    Text(useCase.title)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                            }

                            // Callsign nameplate
                            if !callsign.isEmpty {
                                HStack(spacing: 5) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(accentColor)
                                    Text(callsign)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(accentColor.opacity(0.35), lineWidth: 1))
                            }
                        }

                        MinimapView(
                            trajectory: arState.trajectory,
                            currentPos: SIMD2<Float>(arState.position.x, arState.position.z),
                            heading: arState.heading,
                            pins: arState.pins,
                            peers: arState.peers,
                            walls: arState.walls,
                            accentColor: accentColor,
                            onTap: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    showFullMap = true
                                }
                            }
                        )
                    }

                    Spacer()

                    StatsOverlay(
                        frameCount: frameCount,
                        distance: arState.distanceWalked,
                        features: arState.featureCount,
                        trackingState: arState.trackingState,
                        pinCount: arState.pins.count,
                        elapsed: elapsed,
                        isRelayConnected: arState.isRelayConnected
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)

                Spacer()

                // ── Send status ──────────────────────────────────
                if !sendStatus.isEmpty {
                    Text(sendStatus)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding(.bottom, 8)
                }

                // ── Bottom controls ──────────────────────────────
                HStack(spacing: 16) {
                    // LiDAR toggle
                    Button(action: {
                        lidarLoading = true
                        lidarEnabled.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { lidarLoading = false }
                    }) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(lidarEnabled ? accentColor.opacity(0.15) : Color.black.opacity(0.55))
                                    .frame(width: 44, height: 44)
                                    .overlay(Circle().stroke(lidarEnabled ? accentColor.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1))
                                if lidarLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                                        .scaleEffect(0.75)
                                } else {
                                    Image(systemName: "lidar.scanner")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(lidarEnabled ? accentColor : .white.opacity(0.35))
                                }
                            }
                            Text(lidarLoading ? "Loading..." : lidarEnabled ? "Turn Off" : "Turn On")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(lidarEnabled ? accentColor.opacity(0.8) : .white.opacity(0.35))
                        }
                    }
                    .disabled(lidarLoading)

                    // Pin button — long press for radial wheel
                    ZStack {
                        Circle()
                            .fill(showPinWheel ? accentColor.opacity(0.5) : accentColor)
                            .frame(width: 50, height: 50)
                            .shadow(color: accentColor.opacity(0.4), radius: 8, y: 3)
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .scaleEffect(showPinWheel ? 1.2 : 1.0)
                    }
                    .scaleEffect(showPinWheel ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPinWheel)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                            .onChanged { value in
                                switch value {
                                case .first: break
                                case .second(let longPressed, let drag):
                                    if longPressed && !showPinWheel {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                            showPinWheel = true
                                        }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                    if let drag = drag {
                                        updatePinSelection(dragLoc: drag.location)
                                    }
                                }
                            }
                            .onEnded { _ in
                                if showPinWheel, let idx = selectedPinIndex {
                                    let pin = useCase.pinLabels[idx]
                                    let label = pin.label
                                    ARState.shared.requestDropPin?(label, UIColor(pin.color))
                                    NetworkingManager.shared.sendPin(position: arState.position, label: label)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                withAnimation(.spring(response: 0.25)) { showPinWheel = false }
                                selectedPinIndex = nil
                            }
                    )

                    // Record / Stop button
                    Button(action: {
                        if isRecording {
                            isRecording = false
                            SnapshotManager.shared.stopSession()
                            hasRecording = true
                            recordingStartTime = nil
                        } else {
                            SnapshotManager.shared.startSession()
                            isRecording = true
                            hasRecording = false
                            frameCount = 0
                            sendStatus = ""
                            recordingStartTime = Date()
                            elapsed = 0
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isRecording ? "stop.fill" : "record.circle")
                                .font(.system(size: 18))
                            Text(isRecording ? "Stop" : "Record")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(isRecording ? Color.red : Color.black.opacity(0.75))
                        .cornerRadius(30)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    }

                    // Send to Mac button
                    if hasRecording && !isRecording {
                        Button(action: { sendToMac() }) {
                            HStack(spacing: 8) {
                                if isSending {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.up.to.line")
                                        .font(.system(size: 18))
                                }
                                Text(isSending ? "Sending..." : "Send")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(30)
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        }
                        .disabled(isSending)
                    }
                }
                .padding(.bottom, 80)
            }

            }
            .transition(.opacity.combined(with: .scale(0.98)))
            // ── Pin wheel overlay ────────────────────────────────
            } // end if originLocked
            PinWheelOverlay(
                labels: useCase.pinLabels,
                accentColor: accentColor,
                selectedIndex: selectedPinIndex,
                useCaseId: useCase.id
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .opacity(showPinWheel ? 1 : 0)
            .zIndex(15)

            // ── Full map overlay ─────────────────────────────────
            if showFullMap {
                FullMap3DView(
                    trajectory: arState.trajectory,
                    currentPos: arState.position,
                    heading: arState.heading,
                    pins: arState.pins,
                    peers: arState.peers,
                    walls: arState.walls,
                    floors: arState.floors,
                    accentColor: accentColor,
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFullMap = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            // ── Marker scan overlay ───────────────────────────────
            if !arState.originLocked {
                VStack(spacing: 0) {
                    // Mode badge top
                    HStack {
                        Label(useCase.title.uppercased(), systemImage: useCase.icon)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)

                    Spacer()

                    VStack(spacing: 24) {
                        ScannerCorners(color: accentColor, size: 220)

                        VStack(spacing: 8) {
                            Text("SCAN MARKER")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.white)
                            Text("Point camera at the ArUco marker to begin")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 32)
                    .padding(.bottom, 80)
                }
                .transition(.opacity.combined(with: .scale(1.04)).combined(with: .blurReplace))
                .zIndex(20)
                .allowsHitTesting(false)
            }
        }
        .onReceive(timer) { _ in
            if isRecording {
                frameCount = SnapshotManager.shared.capturedFrameCount
                if let start = recordingStartTime {
                    elapsed = Date().timeIntervalSince(start)
                }
            }
        }
    }

    // MARK: - Pin Wheel Helpers

    private var wheelCenter: CGPoint {
        let s = UIScreen.main.bounds
        return CGPoint(x: s.width / 2, y: s.height * 0.42)
    }

    private func updatePinSelection(dragLoc: CGPoint) {
        let wc = wheelCenter
        let dx = dragLoc.x - wc.x
        let dy = dragLoc.y - wc.y
        let dist = sqrt(dx * dx + dy * dy)

        guard dist > 44 else {
            selectedPinIndex = nil
            return
        }

        let count = useCase.pinLabels.count
        let step = 2 * Double.pi / Double(count)
        let angle = Double(atan2(dy, dx))

        var best = 0
        var bestDiff = Double.infinity
        for i in 0..<count {
            let itemAngle = -Double.pi / 2 + Double(i) * step
            var diff = angle - itemAngle
            while diff >  Double.pi { diff -= 2 * Double.pi }
            while diff < -Double.pi { diff += 2 * Double.pi }
            diff = abs(diff)
            if diff < bestDiff { bestDiff = diff; best = i }
        }
        let newIndex = bestDiff < step / 2 + 0.05 ? best : nil
        if newIndex != selectedPinIndex {
            if newIndex != nil { UISelectionFeedbackGenerator().selectionChanged() }
            selectedPinIndex = newIndex
        }
    }

    // MARK: - Send scan folder to Mac over TCP

    private func sendToMac() {
        guard let sessionPath = SnapshotManager.shared.sessionPath else {
            sendStatus = "No scan data found"
            return
        }

        isSending = true
        sendStatus = "Connecting..."

        DispatchQueue.global(qos: .userInitiated).async {
            let serverIP = NetworkingManager.shared.getServerIP()
            let serverPort: UInt16 = 9877

            do {
                let sessionURL = URL(fileURLWithPath: sessionPath)
                let fm = FileManager.default

                guard let enumerator = fm.enumerator(at: sessionURL, includingPropertiesForKeys: nil) else {
                    DispatchQueue.main.async {
                        sendStatus = "Failed to read scan folder"
                        isSending = false
                    }
                    return
                }

                var fileEntries: [(relativePath: String, url: URL)] = []
                let basePath = sessionURL.standardizedFileURL.path + "/"
                while let fileURL = enumerator.nextObject() as? URL {
                    guard fileURL.isFileURL, !fileURL.hasDirectoryPath else { continue }
                    let filePath = fileURL.standardizedFileURL.path
                    let relativePath = filePath.hasPrefix(basePath)
                        ? String(filePath.dropFirst(basePath.count))
                        : fileURL.lastPathComponent
                    fileEntries.append((relativePath: relativePath, url: fileURL))
                }

                let sock = try Self.createTCPSocket(host: serverIP, port: serverPort)

                try Self.sendPacket(sock: sock, data: NetworkingManager.shared.missionId.data(using: .utf8)!)
                try Self.sendPacket(sock: sock, data: NetworkingManager.shared.clientId.data(using: .utf8)!)
                try Self.sendPacket(sock: sock, data: "\(fileEntries.count)".data(using: .utf8)!)

                for (i, file) in fileEntries.enumerated() {
                    DispatchQueue.main.async {
                        sendStatus = "Sending \(i + 1)/\(fileEntries.count)..."
                    }
                    guard let data = try? Data(contentsOf: file.url) else { continue }
                    try Self.sendPacket(sock: sock, data: file.relativePath.data(using: .utf8)!)
                    try Self.sendPacket(sock: sock, data: data)
                }

                close(sock)
                try? FileManager.default.removeItem(at: sessionURL)

                DispatchQueue.main.async {
                    sendStatus = "Sent \(fileEntries.count) files ✓"
                    isSending = false
                    hasRecording = false
                }

            } catch {
                DispatchQueue.main.async {
                    sendStatus = "Send failed: \(error.localizedDescription)"
                    isSending = false
                }
            }
        }
    }

    // MARK: - TCP Helpers

    private static func createTCPSocket(host: String, port: UInt16) throws -> Int32 {
        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else {
            throw NSError(domain: "socket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result >= 0 else {
            close(sock)
            throw NSError(domain: "socket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to \(host):\(port)"])
        }

        return sock
    }

    private static func sendPacket(sock: Int32, data: Data) throws {
        var length = UInt32(data.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)

        try lengthData.withUnsafeBytes { ptr in
            let sent = send(sock, ptr.baseAddress!, 4, 0)
            if sent < 0 {
                throw NSError(domain: "send", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to send length"])
            }
        }

        try data.withUnsafeBytes { ptr in
            var totalSent = 0
            while totalSent < data.count {
                let sent = send(sock, ptr.baseAddress! + totalSent, data.count - totalSent, 0)
                if sent < 0 {
                    throw NSError(domain: "send", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to send data"])
                }
                totalSent += sent
            }
        }
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var lidarEnabled: Bool
    let callsign: String

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView
        context.coordinator.lastLidarEnabled = lidarEnabled

        let scnView = SCNView(frame: arView.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .clear
        scnView.isOpaque = false
        scnView.rendersContinuously = true
        scnView.isUserInteractionEnabled = false
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = true
        let scnScene = SCNScene()
        scnView.scene = scnScene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 100
        scnScene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
        context.coordinator.scnView = scnView
        context.coordinator.scnCameraNode = cameraNode
        arView.addSubview(scnView)

        let coordinator = context.coordinator

        NetworkingManager.shared.callsign = callsign
        NetworkingManager.shared.onPeerTransformReceived = { [weak coordinator] peerId, transform, peerCallsign in
            coordinator?.updatePeer(peerId, transform: transform, callsign: peerCallsign)
            ARState.shared.updatePeer(peerId, transform: transform, callsign: peerCallsign)
        }

        NetworkingManager.shared.onPinReceived = { position, label in
            ARState.shared.addPin(position: position, label: label, color: .white)
        }

        NetworkingManager.shared.onConnectionChanged = { connected in
            ARState.shared.isRelayConnected = connected
        }

        ARState.shared.onPinAdded = { [weak coordinator] pin, color in
            coordinator?.addPinToScene(pin, color: color)
        }

        ARState.shared.requestDropPin = { [weak coordinator] label, color in
            coordinator?.dropPin(label: label, color: color)
        }

        runSession(arView, lidarEnabled: lidarEnabled)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        guard context.coordinator.lastLidarEnabled != lidarEnabled else { return }
        context.coordinator.lastLidarEnabled = lidarEnabled
        runSession(uiView, lidarEnabled: lidarEnabled)
    }

    private func runSession(_ arView: ARView, lidarEnabled: Bool) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if lidarEnabled && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
        if let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "Origin Reference Images", bundle: nil) {
            configuration.detectionImages = referenceImages
        }
        arView.session.run(configuration)
    }
}

// MARK: - AR Session Coordinator

class Coordinator: NSObject, ARSessionDelegate {
    weak var arView: ARView?
    @Binding var isRecording: Bool
    var lastLidarEnabled: Bool = true
    var scnView: SCNView?
    var scnCameraNode = SCNNode()
    var peerNodes: [String: SCNNode] = [:]       // legacy, kept for compatibility
    var peerAnchors: [String: AnchorEntity] = [:]  // RealityKit peer figures
    var peerFigures: [String: Entity] = [:]          // The solid stick figure entity per peer
    var peerOutlines: [String: Entity] = [:]         // Dashed wireframe shown when occluded
    var peerNameplates: [String: Entity] = [:]       // Nameplate text above peer heads
    var peerCallsigns: [String: String] = [:]        // Cached callsign per peer
    var peerOccluded: [String: Bool] = [:]           // Whether peer is behind a wall/floor
    var peerDistanceLabels: [String: ModelEntity] = [:]  // Distance text below nameplate
    var peerLastDistanceStr: [String: String] = [:]      // Cached to avoid rebuilding every frame
    var peerBackplates: [String: ModelEntity] = [:]      // Background plate behind nameplate
    var peerTrailAnchors: [String: AnchorEntity] = [:]  // RealityKit trail per peer
    var peerTrailCounts: [String: Int] = [:]             // Track point count to know when to rebuild
    var pinAnchors: [UUID: AnchorEntity] = [:]       // RealityKit pin markers
    var pinLabels: [UUID: Entity] = [:]               // RealityKit pin labels
    var pinDistanceFrameCounter: Int = 0
    var subscriptions: [Any] = []
    private var planeAnchors: [UUID: ARPlaneAnchor] = [:]
    private var planeFrameCounter = 0
    private let planeSendEveryN = 60

    private var originSet = false
    private var estimatedFloorY: Float?

    init(isRecording: Binding<Bool>) {
        _isRecording = isRecording
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors.compactMap({ $0 as? ARPlaneAnchor }) {
            planeAnchors[anchor.identifier] = anchor
        }
        for anchor in anchors.compactMap({ $0 as? ARImageAnchor }) {
            print("Detected image: \(anchor.referenceImage.name ?? "unknown")")

            let refImage = anchor.referenceImage
            let mesh = MeshResource.generatePlane(
                width: Float(refImage.physicalSize.width),
                depth: Float(refImage.physicalSize.height)
            )
            var material = SimpleMaterial()
            material.color = .init(tint: .blue.withAlphaComponent(0.25))

            let entity = ModelEntity(mesh: mesh, materials: [material])
            let anchorEntity = AnchorEntity(anchor: anchor)
            anchorEntity.addChild(entity)
            arView?.scene.addAnchor(anchorEntity)

            guard !originSet else { continue }
            originSet = true

            let anchorMatrix = anchor.transform
            let position = anchorMatrix.columns.3

            // Use the marker's X axis (column 0) projected onto XZ as the consistent forward.
            // Both players scanning the same marker get the same world orientation.
            let col0xz = simd_float3(anchorMatrix.columns.0.x, 0, anchorMatrix.columns.0.z)
            let col2xz = simd_float3(anchorMatrix.columns.2.x, 0, anchorMatrix.columns.2.z)
            let forward: simd_float3
            if simd_length(col0xz) > 0.1 {
                forward = simd_normalize(col0xz)
            } else {
                forward = simd_normalize(col2xz)
            }

            let up = simd_float3(0, 1, 0)
            let right = simd_normalize(simd_cross(up, forward))

            var gravityAlignedMatrix = matrix_identity_float4x4
            gravityAlignedMatrix.columns.0 = simd_float4(right, 0)
            gravityAlignedMatrix.columns.1 = simd_float4(up, 0)
            gravityAlignedMatrix.columns.2 = simd_float4(forward, 0)
            gravityAlignedMatrix.columns.3 = position

            session.setWorldOrigin(relativeTransform: gravityAlignedMatrix)

            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.5)) {
                    ARState.shared.originLocked = true
                }
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors.compactMap({ $0 as? ARPlaneAnchor }) {
            planeAnchors[anchor.identifier] = anchor
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors.compactMap({ $0 as? ARPlaneAnchor }) {
            planeAnchors.removeValue(forKey: anchor.identifier)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        ARState.shared.update(frame: frame)
        guard ARState.shared.originLocked else { return }
        planeFrameCounter += 1
        if planeFrameCounter % planeSendEveryN == 0 {
            sendCurrentPlanes()
        }
        NetworkingManager.shared.processFrame(frame)
        if isRecording {
            SnapshotManager.shared.processFrame(frame)
        }
        if scnView != nil {
            scnCameraNode.simdTransform = frame.camera.transform
            let res = frame.camera.imageResolution
            let fy = frame.camera.intrinsics.columns.1.y
            scnCameraNode.camera?.fieldOfView = CGFloat(2 * atan(Float(res.height) / (2 * fy)) * 180 / .pi)

        }
        updatePinLabels(cameraTransform: frame.camera.transform)
        updateFloorEstimate()
        pruneStalePeers()
        updatePeerTrails()
    }

    private func updateFloorEstimate() {
        var lowestY: Float? = nil
        for anchor in planeAnchors.values {
            guard anchor.alignment == .horizontal else { continue }
            let y = anchor.transform.columns.3.y + anchor.center.y
            if lowestY == nil || y < lowestY! {
                lowestY = y
            }
        }
        if let y = lowestY {
            let isFirst = estimatedFloorY == nil
            // Smooth it to avoid jitter
            if let current = estimatedFloorY {
                estimatedFloorY = current * 0.9 + y * 0.1
            } else {
                estimatedFloorY = y
            }
            // Force trail rebuild when floor is first detected
            if isFirst {
                peerTrailCounts.removeAll()
            }
        }
    }

    // MARK: - Plane Streaming

    private func sendCurrentPlanes() {
        let planesData: [[String: Any]] = planeAnchors.values.map { anchor in
            let t = anchor.transform
            let c = anchor.center
            let wc = t * SIMD4<Float>(c.x, c.y, c.z, 1)
            let e = anchor.extent
            return [
                "id": anchor.identifier.uuidString,
                "alignment": anchor.alignment == .horizontal ? "horizontal" : "vertical",
                "center": [wc.x, wc.y, wc.z],
                "extent": [e.x, e.z],
                "transform": [
                    t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
                    t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
                    t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
                    t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
                ] as [Float]
            ]
        }
        NetworkingManager.shared.sendPlanes(planesData)
        ARState.shared.updateLocalPlanes(planesData)
    }

    // MARK: - Peer Avatars (RealityKit — rendered directly in ARView)

    func updatePeer(_ peerId: String, transform: simd_float4x4, callsign: String = "") {
        guard let arView = arView else { return }

        if peerAnchors[peerId] == nil {
            let anchor = AnchorEntity(world: .zero)
            let figure = PeerModel.makeEntity(color: UIColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.85))
            // Shift figure down so head aligns with peer's camera (phone) position
            figure.position.y = -0.80
            anchor.addChild(figure)
            let outline = PeerModel.makeOutlineEntity(color: UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.85))
            outline.position.y = -0.80
            outline.isEnabled = false
            anchor.addChild(outline)
            arView.scene.addAnchor(anchor)
            peerAnchors[peerId] = anchor
            peerFigures[peerId] = figure
            peerOutlines[peerId] = outline
        }

        // Add or update nameplate
        if !callsign.isEmpty && callsign != peerCallsigns[peerId] {
            print("[Nameplate] Creating nameplate for peer \(peerId.prefix(8)): '\(callsign)'")
            // Remove old nameplate
            peerNameplates[peerId]?.removeFromParent()
            peerBackplates.removeValue(forKey: peerId)
            peerDistanceLabels.removeValue(forKey: peerId)
            peerLastDistanceStr.removeValue(forKey: peerId)

            let nameplateContainer = Entity()
            let nameplate = PeerModel.makeNameplate(text: callsign)
            nameplateContainer.addChild(nameplate)

            // Add background plate (will be resized once distance label is added)
            let nameBounds = nameplate.visualBounds(relativeTo: nameplate.parent)
            let plateW = nameBounds.extents.x + 0.04
            let plateH = nameBounds.extents.y + 0.14  // extra room for distance text
            let plateMesh = MeshResource.generatePlane(width: plateW, height: plateH, cornerRadius: 0.01)
            var plateMat = UnlitMaterial()
            plateMat.color = .init(tint: UIColor(white: 1.0, alpha: 0.75))
            let plate = ModelEntity(mesh: plateMesh, materials: [plateMat])
            plate.position = SIMD3<Float>(0, nameBounds.center.y - 0.03, -0.003)  // slightly behind text
            nameplateContainer.addChild(plate)
            peerBackplates[peerId] = plate

            // Position directly above head
            nameplateContainer.position = [0, 0.30, 0]
            peerAnchors[peerId]?.addChild(nameplateContainer)
            peerNameplates[peerId] = nameplateContainer
            peerCallsigns[peerId] = callsign
        }

        let anchor = peerAnchors[peerId]!
        let pos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let yaw = atan2(-transform.columns.2.x, -transform.columns.2.z)

        // Extract pitch from transform (angle the phone is tilted up/down)
        let fwd = SIMD3<Float>(-transform.columns.2.x, -transform.columns.2.y, -transform.columns.2.z)
        let pitch = asin(max(-1, min(1, fwd.y))) // positive = looking up

        anchor.position = pos
        anchor.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

        // Estimate height above floor and apply pose
        let cameraHeight: Float
        if let floorY = estimatedFloorY {
            cameraHeight = pos.y - floorY
        } else {
            cameraHeight = 1.6 // assume standing if no floor detected
        }
        if let figure = peerFigures[peerId] {
            PeerModel.applyPose(to: figure, pitch: pitch, heightAboveFloor: cameraHeight)
        }

        // Billboard the nameplate toward the camera
        if let cameraTransform = arView.session.currentFrame?.camera.transform {
            let camPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)

            if let nameplate = peerNameplates[peerId] {
                let nameplateWorldPos = pos + SIMD3<Float>(0, 0.30, 0)
                let direction = camPos - nameplateWorldPos
                let billboardYaw = atan2(direction.x, direction.z)
                nameplate.orientation = simd_quatf(angle: billboardYaw - yaw, axis: [0, 1, 0])

                // Update distance label
                let dist = simd_distance(camPos, pos)
                let distStr: String
                if dist < 1.0 {
                    distStr = String(format: "%.1fm", dist)
                } else {
                    distStr = String(format: "%.0fm", dist)
                }
                if distStr != peerLastDistanceStr[peerId] {
                    peerDistanceLabels[peerId]?.removeFromParent()
                    let label = PeerModel.makeNameplate(text: distStr)
                    label.scale = SIMD3<Float>(repeating: 0.7)
                    label.position.y = -0.10
                    nameplate.addChild(label)
                    peerDistanceLabels[peerId] = label
                    peerLastDistanceStr[peerId] = distStr

                    // Resize backplate to fit both callsign + distance
                    if let plate = peerBackplates[peerId] {
                        let containerBounds = nameplate.visualBounds(relativeTo: nil)
                        let plateW = containerBounds.extents.x + 0.04
                        let plateH = containerBounds.extents.y + 0.04
                        plate.model?.mesh = MeshResource.generatePlane(width: plateW, height: plateH, cornerRadius: 0.01)
                        plate.position = SIMD3<Float>(0, containerBounds.center.y, -0.003)
                    }
                }
            }

            // Solid figure always hidden; dashed outline only when behind a wall
            peerFigures[peerId]?.isEnabled = false
            let occluded = isPeerOccluded(cameraPos: camPos, peerPos: pos)
            if occluded != (peerOccluded[peerId] ?? false) {
                peerOccluded[peerId] = occluded
                peerOutlines[peerId]?.isEnabled = occluded
            }
        }
    }

    private func applyMaterials(_ entity: Entity, color: UIColor, occluded: Bool) {
        for child in entity.children {
            if let model = child as? ModelEntity {
                var mat = UnlitMaterial()
                mat.color = .init(tint: occluded ? color.withAlphaComponent(0.2) : color)
                model.model?.materials = [mat]
            }
            applyMaterials(child, color: color, occluded: occluded)
        }
    }

    private func isPeerOccluded(cameraPos: SIMD3<Float>, peerPos: SIMD3<Float>) -> Bool {
        let ray = peerPos - cameraPos
        let rayLen = simd_length(ray)
        guard rayLen > 0.3 else { return false }
        let rayDir = ray / rayLen

        // Check walls
        for wall in ARState.shared.walls {
            let wallNormal = SIMD3<Float>(-wall.xDirXZ.y, 0, wall.xDirXZ.x)
            let denom = simd_dot(rayDir, wallNormal)
            guard abs(denom) > 0.001 else { continue }

            let t = simd_dot(wall.center - cameraPos, wallNormal) / denom
            guard t > 0.2 && t < rayLen - 0.2 else { continue }

            let hitPoint = cameraPos + rayDir * t
            let localOffset = hitPoint - wall.center
            let alongWall = abs(simd_dot(SIMD3<Float>(wall.xDirXZ.x, 0, wall.xDirXZ.y), localOffset))
            let alongHeight = abs(localOffset.y)

            if alongWall <= wall.width / 2 && alongHeight <= wall.height / 2 {
                return true
            }
        }

        // Check floors (horizontal planes between camera and peer)
        for floor in ARState.shared.floors {
            let floorY = floor.center.y
            // Floor normal is (0, 1, 0)
            guard abs(rayDir.y) > 0.001 else { continue }
            let t = (floorY - cameraPos.y) / rayDir.y
            guard t > 0.2 && t < rayLen - 0.2 else { continue }

            let hitPoint = cameraPos + rayDir * t
            let localOffset = SIMD2<Float>(hitPoint.x - floor.center.x, hitPoint.z - floor.center.z)
            let alongX = abs(simd_dot(floor.xDirXZ, localOffset))
            let perpDir = SIMD2<Float>(-floor.xDirXZ.y, floor.xDirXZ.x)
            let alongZ = abs(simd_dot(perpDir, localOffset))

            if alongX <= floor.widthX / 2 && alongZ <= floor.depthZ / 2 {
                return true
            }
        }

        return false
    }

    private func pruneStalePeers() {
        guard let arView = arView else { return }
        let activeIds = Set(ARState.shared.peers.keys)
        for id in Array(peerAnchors.keys) where !activeIds.contains(id) {
            peerAnchors[id]?.removeFromParent()
            peerAnchors.removeValue(forKey: id)
            peerFigures.removeValue(forKey: id)
            peerOutlines.removeValue(forKey: id)
            peerNameplates.removeValue(forKey: id)
            peerCallsigns.removeValue(forKey: id)
            peerOccluded.removeValue(forKey: id)
            peerDistanceLabels.removeValue(forKey: id)
            peerLastDistanceStr.removeValue(forKey: id)
            peerBackplates.removeValue(forKey: id)
            peerTrailAnchors[id]?.removeFromParent()
            peerTrailAnchors.removeValue(forKey: id)
            peerTrailCounts.removeValue(forKey: id)
        }
    }

    // MARK: - Peer AR Trails

    private static let trailPalette: [UIColor] = [
        UIColor(red: 0.91, green: 0.40, blue: 0.35, alpha: 1),
        UIColor(red: 0.36, green: 0.56, blue: 0.84, alpha: 1),
        UIColor(red: 0.67, green: 0.28, blue: 0.74, alpha: 1),
        UIColor(red: 0.15, green: 0.78, blue: 0.85, alpha: 1),
        UIColor(red: 1.0,  green: 0.44, blue: 0.26, alpha: 1),
        UIColor(red: 0.55, green: 0.76, blue: 0.29, alpha: 1),
    ]

    private func trailColor(for peerId: String) -> UIColor {
        Self.trailPalette[abs(peerId.hashValue) % Self.trailPalette.count]
    }

    private func updatePeerTrails() {
        guard let arView = arView else { return }
        let peers = ARState.shared.peers

        for (peerId, state) in peers {
            let count = state.trajectory.count
            // Only rebuild when 5+ new points arrive
            if count == (peerTrailCounts[peerId] ?? 0) { continue }
            if count - (peerTrailCounts[peerId] ?? 0) < 5 && count > 5 { continue }

            // Remove old trail anchor
            peerTrailAnchors[peerId]?.removeFromParent()
            peerTrailAnchors.removeValue(forKey: peerId)

            if let entity = makeTrailEntity(trajectory: state.trajectory, color: trailColor(for: peerId)) {
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)
                peerTrailAnchors[peerId] = anchor
            }
            peerTrailCounts[peerId] = count
        }
    }

    private func makeTrailEntity(trajectory: [simd_float4x4], color: UIColor) -> ModelEntity? {
        // Estimate how far the camera is above the floor so we can offset trail to foot level
        let cameraHeight: Float
        if let floorY = estimatedFloorY,
           let frame = arView?.session.currentFrame {
            cameraHeight = frame.camera.transform.columns.3.y - floorY
        } else {
            cameraHeight = 1.5 // reasonable fallback
        }
        let halfWidth: Float = 0.03

        // Deduplicate points, keeping actual Y (offset to foot level)
        var pts: [SIMD3<Float>] = []
        for t in trajectory {
            let footY = t.columns.3.y - cameraHeight + 0.02
            let p = SIMD3<Float>(t.columns.3.x, footY, t.columns.3.z)
            if let last = pts.last {
                let dx = p.x - last.x, dy = p.y - last.y, dz = p.z - last.z
                guard dx * dx + dy * dy + dz * dz > 0.0001 else { continue }
            }
            pts.append(p)
        }
        guard pts.count >= 2 else { return nil }

        // Build a ribbon mesh that follows the 3D path
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var normals: [SIMD3<Float>] = []

        for i in 0..<pts.count {
            // Direction vector along the trail in XZ
            let dir: SIMD2<Float>
            if i == 0 {
                dir = simd_normalize(SIMD2(pts[1].x - pts[0].x, pts[1].z - pts[0].z))
            } else if i == pts.count - 1 {
                dir = simd_normalize(SIMD2(pts[i].x - pts[i-1].x, pts[i].z - pts[i-1].z))
            } else {
                let raw = SIMD2(pts[i+1].x - pts[i-1].x, pts[i+1].z - pts[i-1].z)
                let len = simd_length(raw)
                dir = len > 0.001 ? raw / len : SIMD2(1, 0)
            }

            // Perpendicular in XZ plane
            let perp = SIMD2(-dir.y, dir.x) * halfWidth
            let y = pts[i].y

            positions.append(SIMD3(pts[i].x + perp.x, y, pts[i].z + perp.y))
            positions.append(SIMD3(pts[i].x - perp.x, y, pts[i].z - perp.y))
            normals.append(SIMD3(0, 1, 0))
            normals.append(SIMD3(0, 1, 0))
        }

        for i in 0..<(pts.count - 1) {
            let base = UInt32(i * 2)
            // Two triangles per quad
            indices.append(contentsOf: [base, base + 2, base + 1])
            indices.append(contentsOf: [base + 1, base + 2, base + 3])
        }

        var descriptor = MeshDescriptor(name: "trail")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        var mat = UnlitMaterial()
        mat.color = .init(tint: color.withAlphaComponent(0.75))
        let entity = ModelEntity(mesh: mesh, materials: [mat])
        return entity
    }

    // MARK: - Pin Placement via Raycast

    func dropPin(label: String, color: UIColor) {
        guard let arView = arView else { return }

        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let results = arView.raycast(from: screenCenter,
                                     allowing: .estimatedPlane,
                                     alignment: .any)

        // Determine floor Y: use detected floor or fallback to camera height minus ~1.5m
        let floorY: Float
        if let fy = estimatedFloorY {
            floorY = fy
        } else if let frame = arView.session.currentFrame {
            floorY = frame.camera.transform.columns.3.y - 1.5
        } else {
            floorY = ARState.shared.position.y - 1.5
        }

        let position: SIMD3<Float>
        if let hit = results.first {
            let c = hit.worldTransform.columns.3
            // Snap to floor Y so pin never floats
            position = SIMD3<Float>(c.x, floorY, c.z)
        } else if let frame = arView.session.currentFrame {
            // No raycast hit — project forward along camera direction onto floor plane
            let cam = frame.camera.transform
            let fwd = SIMD3<Float>(-cam.columns.2.x, -cam.columns.2.y, -cam.columns.2.z)
            let org = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
            // Intersect camera ray with floor plane
            let t = (floorY - org.y) / fwd.y
            if t > 0.3 && t < 10.0 {
                let hitPoint = org + fwd * t
                position = SIMD3<Float>(hitPoint.x, floorY, hitPoint.z)
            } else {
                // Looking up or too far — place 2.5m ahead on the floor
                let ahead = org + simd_normalize(SIMD3<Float>(fwd.x, 0, fwd.z)) * 2.5
                position = SIMD3<Float>(ahead.x, floorY, ahead.z)
            }
        } else {
            position = SIMD3<Float>(ARState.shared.position.x, floorY, ARState.shared.position.z)
        }

        ARState.shared.addPin(position: position, label: label, color: color)
    }

    // MARK: - Pin Entity Creation (RealityKit — self-contained orientation)

    func addPinToScene(_ pin: MapPin, color: UIColor) {
        guard let arView = arView else { return }

        // Pin marker (stick + sphere + ring)
        let pinEntity = PinRenderer.makePinEntity(color: color)
        let pinAnchor = AnchorEntity(world: pin.position)
        pinAnchor.addChild(pinEntity)
        arView.scene.addAnchor(pinAnchor)
        pinAnchors[pin.id] = pinAnchor

        // Label (text + colored plate)
        let labelEntity = PinRenderer.makeLabelEntity(text: pin.label, color: color)
        let labelAnchor = AnchorEntity(world: SIMD3<Float>(pin.position.x, pin.position.y + 0.55, pin.position.z))
        labelAnchor.addChild(labelEntity)
        arView.scene.addAnchor(labelAnchor)
        pinLabels[pin.id] = labelEntity
    }

    // MARK: - Pin Updates

    func updatePinLabels(cameraTransform: simd_float4x4) {
        pinDistanceFrameCounter += 1
        guard pinDistanceFrameCounter % 10 == 0 else { return }

        PinRenderer.updatePins(
            pinAnchors: pinAnchors,
            pinLabels: pinLabels,
            pins: ARState.shared.pins,
            cameraTransform: cameraTransform
        )
    }
}

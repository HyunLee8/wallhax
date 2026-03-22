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
            ARViewContainer(isRecording: $isRecording, lidarEnabled: $lidarEnabled)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)

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
                                    let label = useCase.pinLabels[idx].label
                                    ARState.shared.requestDropPin?(label, UIColor(accentColor))
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

            // ── Pin wheel overlay ────────────────────────────────
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

        NetworkingManager.shared.onPeerTransformReceived = { [weak coordinator] peerId, transform in
            coordinator?.updatePeer(peerId, transform: transform)
            ARState.shared.updatePeer(peerId, transform: transform)
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

        coordinator.subscriptions.append(
            arView.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator] _ in
                coordinator?.updatePinBobbing()
            }
        )

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
    var peerNodes: [String: SCNNode] = [:]
    var pinAnchors: [UUID: AnchorEntity] = [:]
    var pinBobEntities: [UUID: (entity: Entity, phase: Float)] = [:]
    var pinDistanceNodes: [UUID: SCNNode] = [:]
    var distanceFrameCounter: Int = 0
    var subscriptions: [Any] = []
    private var planeAnchors: [UUID: ARPlaneAnchor] = [:]
    private var planeFrameCounter = 0
    private let planeSendEveryN = 60

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

            let anchorMatrix = anchor.transform
            let position = anchorMatrix.columns.3

            var forward = simd_float3(anchorMatrix.columns.1.x, 0, anchorMatrix.columns.1.z)
            if simd_length(forward) < 0.001 {
                forward = simd_float3(anchorMatrix.columns.2.x, 0, anchorMatrix.columns.2.z)
            }
            forward = simd_normalize(forward)

            let up = simd_float3(0, 1, 0)
            let right = simd_normalize(simd_cross(up, forward))

            var gravityAlignedMatrix = matrix_identity_float4x4
            gravityAlignedMatrix.columns.0 = simd_float4(right, 0)
            gravityAlignedMatrix.columns.1 = simd_float4(up, 0)
            gravityAlignedMatrix.columns.2 = simd_float4(forward, 0)
            gravityAlignedMatrix.columns.3 = position

            session.setWorldOrigin(relativeTransform: gravityAlignedMatrix)
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
        planeFrameCounter += 1
        if planeFrameCounter % planeSendEveryN == 0 {
            sendCurrentPlanes()
        }
        NetworkingManager.shared.processFrame(frame)
        ARState.shared.update(frame: frame)
        if isRecording {
            SnapshotManager.shared.processFrame(frame)
        }
        if scnView != nil {
            scnCameraNode.simdTransform = frame.camera.transform
            let res = frame.camera.imageResolution
            let fy = frame.camera.intrinsics.columns.1.y
            scnCameraNode.camera?.fieldOfView = CGFloat(2 * atan(Float(res.height) / (2 * fy)) * 180 / .pi)
            pruneStalePeerCylinders()
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

    // MARK: - Peer Avatars

    func updatePeer(_ peerId: String, transform: simd_float4x4) {
        guard let scene = scnView?.scene else { return }
        if peerNodes[peerId] == nil {
            let node = PeerModel.makeNode(color: UIColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.85))
            scene.rootNode.addChildNode(node)
            peerNodes[peerId] = node
        }
        let node = peerNodes[peerId]!
        let pos = transform.columns.3
        node.simdPosition = SIMD3<Float>(pos.x, pos.y, pos.z)
        node.simdEulerAngles = SIMD3<Float>(0, atan2(-transform.columns.2.x, -transform.columns.2.z), 0)
    }

    private func pruneStalePeerCylinders() {
        let activeIds = Set(ARState.shared.peers.keys)
        for id in Array(peerNodes.keys) where !activeIds.contains(id) {
            peerNodes[id]?.removeFromParentNode()
            peerNodes.removeValue(forKey: id)
        }
    }

    // MARK: - Pin Placement via Raycast

    func dropPin(label: String, color: UIColor) {
        guard let arView = arView else { return }

        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let results = arView.raycast(from: screenCenter,
                                     allowing: .estimatedPlane,
                                     alignment: .any)

        let position: SIMD3<Float>
        if let hit = results.first {
            let c = hit.worldTransform.columns.3
            position = SIMD3<Float>(c.x, c.y, c.z)
        } else if let frame = arView.session.currentFrame {
            let cam = frame.camera.transform
            let fwd = SIMD3<Float>(-cam.columns.2.x, -cam.columns.2.y, -cam.columns.2.z)
            let org = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
            position = org + simd_normalize(fwd) * 2.5
        } else {
            position = ARState.shared.position
        }

        ARState.shared.addPin(position: position, label: label, color: color)
    }

    // MARK: - Pin Entity Creation

    func addPinToScene(_ pin: MapPin, color: UIColor) {
        guard let arView = arView else { return }

        let pillarH: Float = 3.0
        let white = UIColor.white
        let anchor = AnchorEntity(world: pin.position)

        // Light pillar — layered concentric cylinders, bright core fading outward
        let layers: [(radius: Float, alpha: Float)] = [
            (0.008, 1.00),   // bright core
            (0.022, 0.55),
            (0.055, 0.22),
            (0.110, 0.09),
            (0.200, 0.03),
        ]
        for layer in layers {
            let e = ModelEntity(
                mesh: .generateCylinder(height: pillarH, radius: layer.radius),
                materials: [UnlitMaterial(color: white.withAlphaComponent(CGFloat(layer.alpha)))]
            )
            e.position = [0, pillarH / 2, 0]
            anchor.addChild(e)
        }

        // Ground bloom — soft bright disc at base
        let groundLayers: [(radius: Float, alpha: Float)] = [
            (0.06,  0.90),
            (0.14,  0.40),
            (0.28,  0.15),
            (0.50,  0.05),
        ]
        for g in groundLayers {
            let e = ModelEntity(
                mesh: .generateCylinder(height: 0.003, radius: g.radius),
                materials: [UnlitMaterial(color: white.withAlphaComponent(CGFloat(g.alpha)))]
            )
            e.position = [0, 0.0015, 0]
            anchor.addChild(e)
        }

        arView.scene.addAnchor(anchor)
        pinAnchors[pin.id] = anchor

        // Grow from ground
        anchor.scale = [1, 0.001, 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            anchor.move(to: Transform(scale: .one), relativeTo: nil,
                        duration: 0.6, timingFunction: .easeOut)
        }

        addPinDistanceLabel(pin: pin, color: white)
    }

    private func addPinDistanceLabel(pin: MapPin, color: UIColor) {
        guard let scene = scnView?.scene else { return }

        let textGeom = SCNText(string: pin.label + "\n– m", extrusionDepth: 0)
        textGeom.font = UIFont.systemFont(ofSize: 0.22, weight: .bold)
        textGeom.flatness = 0.005
        textGeom.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.white
        mat.emission.contents = color
        mat.isDoubleSided = true
        textGeom.materials = [mat]

        let node = SCNNode(geometry: textGeom)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2, 0, 0)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.position = SCNVector3(pin.position.x, pin.position.y + 3.3, pin.position.z)

        scene.rootNode.addChildNode(node)
        pinDistanceNodes[pin.id] = node
    }

    // MARK: - Idle Bob Animation + Distance Updates

    func updatePinBobbing() {
        distanceFrameCounter += 1
        guard distanceFrameCounter % 30 == 0 else { return }

        let cam = ARState.shared.position
        for pin in ARState.shared.pins {
            guard let node = pinDistanceNodes[pin.id],
                  let textGeom = node.geometry as? SCNText else { continue }
            let dx = pin.position.x - cam.x
            let dy = pin.position.y - cam.y
            let dz = pin.position.z - cam.z
            let dist = sqrt(dx*dx + dy*dy + dz*dz)
            let distStr = dist < 10 ? String(format: "%.1f m", dist) : String(format: "%.0f m", dist)
            textGeom.string = pin.label + "\n" + distStr
        }
    }
}

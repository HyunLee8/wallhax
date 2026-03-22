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
                .transition(.opacity)
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
    var peerNodes: [String: SCNNode] = [:]       // legacy, kept for compatibility
    var peerAnchors: [String: AnchorEntity] = [:]  // RealityKit peer figures
    var pinNodes: [UUID: SCNNode] = [:]
    var pinDistanceNodes: [UUID: SCNNode] = [:]
    var distanceFrameCounter: Int = 0
    var subscriptions: [Any] = []
    private var planeAnchors: [UUID: ARPlaneAnchor] = [:]
    private var planeFrameCounter = 0
    private let planeSendEveryN = 60

    private var originSet = false

    // Auto-pin tracking for detected objects
    private var detectionTracker: [String: (center: CGPoint, firstSeen: TimeInterval)] = [:]
    private var autoPinnedRegions: [CGPoint] = []
    private let autoPinDelay: TimeInterval = 1.5

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

            // Pick the anchor axis with the largest horizontal (XZ) projection.
            // This is more robust than a fixed column with threshold fallback,
            // because it works for markers on walls, floors, or tilted surfaces.
            let col0 = simd_float3(anchorMatrix.columns.0.x, 0, anchorMatrix.columns.0.z)
            let col1 = simd_float3(anchorMatrix.columns.1.x, 0, anchorMatrix.columns.1.z)
            let col2 = simd_float3(anchorMatrix.columns.2.x, 0, anchorMatrix.columns.2.z)
            let len0 = simd_length(col0)
            let len1 = simd_length(col1)
            let len2 = simd_length(col2)

            var forward: simd_float3
            if len1 >= len0 && len1 >= len2 {
                forward = col1
            } else if len0 >= len2 {
                forward = col0
            } else {
                forward = col2
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

            DispatchQueue.main.async {
                ARState.shared.originLocked = true
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
        planeFrameCounter += 1
        if planeFrameCounter % planeSendEveryN == 0 {
            sendCurrentPlanes()
        }
        NetworkingManager.shared.processFrame(frame)
        ARState.shared.update(frame: frame)
        ObjectDetector.shared.processFrame(frame)
        processAutoPin(frame: frame)
        if isRecording {
            SnapshotManager.shared.processFrame(frame)
        }
        if scnView != nil {
            scnCameraNode.simdTransform = frame.camera.transform
            let res = frame.camera.imageResolution
            let fy = frame.camera.intrinsics.columns.1.y
            scnCameraNode.camera?.fieldOfView = CGFloat(2 * atan(Float(res.height) / (2 * fy)) * 180 / .pi)
        }
        pruneStalePeers()
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

    func updatePeer(_ peerId: String, transform: simd_float4x4) {
        guard let arView = arView else { return }

        if peerAnchors[peerId] == nil {
            let anchor = AnchorEntity(world: .zero)
            let figure = PeerModel.makeEntity(color: UIColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 0.85))
            // Shift figure down so head aligns with peer's camera (phone) position
            figure.position.y = -0.80
            anchor.addChild(figure)
            arView.scene.addAnchor(anchor)
            peerAnchors[peerId] = anchor
        }

        let anchor = peerAnchors[peerId]!
        let pos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let yaw = atan2(-transform.columns.2.x, -transform.columns.2.z)

        anchor.position = pos
        anchor.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    private func pruneStalePeers() {
        guard let arView = arView else { return }
        let activeIds = Set(ARState.shared.peers.keys)
        for id in Array(peerAnchors.keys) where !activeIds.contains(id) {
            peerAnchors[id]?.removeFromParent()
            peerAnchors.removeValue(forKey: id)
        }
    }

    // MARK: - Auto-Pin from Object Detection

    func processAutoPin(frame: ARFrame) {
        let objects = ARState.shared.detectedObjects
        let now = frame.timestamp
        var newTracker: [String: (center: CGPoint, firstSeen: TimeInterval)] = [:]

        for obj in objects {
            let center = CGPoint(x: obj.normalizedBounds.midX, y: obj.normalizedBounds.midY)

            var matched = false
            for (key, tracked) in detectionTracker where key.hasPrefix(obj.type) {
                let dist = hypot(center.x - tracked.center.x, center.y - tracked.center.y)
                if dist < 0.1 {
                    newTracker[key] = (center: center, firstSeen: tracked.firstSeen)
                    let elapsed = now - tracked.firstSeen

                    if elapsed >= autoPinDelay && !isRegionPinned(center) {
                        autoPinAt(center: center, label: obj.type)
                        autoPinnedRegions.append(center)
                    }
                    matched = true
                    break
                }
            }

            if !matched {
                let key = "\(obj.type)_\(Int.random(in: 0...9999))"
                newTracker[key] = (center: center, firstSeen: now)
            }
        }
        detectionTracker = newTracker
    }

    private func isRegionPinned(_ center: CGPoint) -> Bool {
        autoPinnedRegions.contains { p in hypot(center.x - p.x, center.y - p.y) < 0.15 }
    }

    private func autoPinAt(center: CGPoint, label: String) {
        guard let arView = arView else { return }
        let screenSize = arView.bounds.size
        let screenPoint = CGPoint(
            x: center.x * screenSize.width,
            y: (1 - center.y) * screenSize.height
        )

        let results = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        let position: SIMD3<Float>
        if let hit = results.first {
            let c = hit.worldTransform.columns.3
            position = SIMD3<Float>(c.x, c.y, c.z)
        } else if let frame = arView.session.currentFrame {
            let cam = frame.camera.transform
            let fwd = SIMD3<Float>(-cam.columns.2.x, -cam.columns.2.y, -cam.columns.2.z)
            let org = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
            position = org + simd_normalize(fwd) * 3.0
        } else { return }

        // Don't pin too close to existing pins
        let tooClose = ARState.shared.pins.contains { simd_distance($0.position, position) < 1.5 }
        guard !tooClose else { return }

        ARState.shared.addPin(position: position, label: label, color: .white)
        NetworkingManager.shared.sendPin(position: position, label: label)
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
        guard let scene = scnView?.scene else { return }

        let pillarH: CGFloat = 0.8
        let warmWhite = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1.0)

        let root = SCNNode()
        root.position = SCNVector3(pin.position.x, pin.position.y, pin.position.z)

        // ── Additive-blend helper ───────────────────────────────
        // blendMode = .add makes each layer ADD brightness to the
        // scene rather than painting over it. This is how real
        // light works — overlapping glow builds up intensity, and
        // you see right through the outer halo. Combined with
        // emission (self-lit, ignores scene lighting) this creates
        // genuine volumetric-looking light.

        func glowMaterial(color: UIColor, alpha: CGFloat) -> SCNMaterial {
            let mat = SCNMaterial()
            let c = color.withAlphaComponent(alpha)
            mat.diffuse.contents = UIColor.clear
            mat.emission.contents = c
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            mat.readsFromDepthBuffer = false
            mat.isDoubleSided = true
            mat.transparent.contents = c
            return mat
        }

        // ── Core Pillar ─────────────────────────────────────────
        // Tight, bright center — looks like a solid rod of light.
        // Each layer slightly shorter than the last for taper.
        let coreLayers: [(r: CGFloat, a: CGFloat, hs: CGFloat)] = [
            (0.004, 1.00, 1.00),   // needle-bright center
            (0.009, 0.85, 1.00),
            (0.016, 0.60, 0.98),
            (0.026, 0.40, 0.96),
        ]
        for layer in coreLayers {
            let h = pillarH * layer.hs
            let cyl = SCNCylinder(radius: layer.r, height: h)
            cyl.radialSegmentCount = 16
            cyl.materials = [glowMaterial(color: warmWhite, alpha: layer.a)]
            let n = SCNNode(geometry: cyl)
            n.position = SCNVector3(0, Float(h / 2), 0)
            root.addChildNode(n)
        }

        // ── Outer Glow ──────────────────────────────────────────
        // Wider, softer halos that get shorter toward the outside.
        // With additive blending these are genuinely translucent —
        // the AR camera feed shows right through them, tinted with
        // warm light. This is the "defined edges but not solid" look.
        let glowLayers: [(r: CGFloat, a: CGFloat, hs: CGFloat)] = [
            (0.040, 0.28, 0.93),
            (0.065, 0.16, 0.86),
            (0.100, 0.09, 0.78),
            (0.160, 0.045, 0.66),
            (0.250, 0.018, 0.52),
            (0.380, 0.006, 0.38),
        ]
        for layer in glowLayers {
            let h = pillarH * layer.hs
            let cyl = SCNCylinder(radius: layer.r, height: h)
            cyl.radialSegmentCount = 24
            cyl.materials = [glowMaterial(color: warmWhite, alpha: layer.a)]
            let n = SCNNode(geometry: cyl)
            n.position = SCNVector3(0, Float(h / 2), 0)
            root.addChildNode(n)
        }

        // ── Ground Bloom ────────────────────────────────────────
        // Pool of light on the ground — additive so it brightens
        // the floor beneath rather than painting a white disc.
        let bloomLayers: [(r: CGFloat, a: CGFloat)] = [
            (0.05,  0.80),
            (0.10,  0.45),
            (0.18,  0.22),
            (0.30,  0.10),
            (0.50,  0.035),
            (0.75,  0.010),
        ]
        for g in bloomLayers {
            let disc = SCNCylinder(radius: g.r, height: 0.003)
            disc.materials = [glowMaterial(color: warmWhite, alpha: g.a)]
            let n = SCNNode(geometry: disc)
            n.position = SCNVector3(0, 0.0015, 0)
            root.addChildNode(n)
        }

        // ── Top Dissipation ─────────────────────────────────────
        // The pillar doesn't just cut off — it feathers into
        // nothing, like light scattering at the top of the crystal
        // column.
        let capLayers: [(r: CGFloat, a: CGFloat)] = [
            (0.03, 0.25),
            (0.08, 0.10),
            (0.15, 0.03),
        ]
        for c in capLayers {
            let disc = SCNCylinder(radius: c.r, height: 0.004)
            disc.materials = [glowMaterial(color: warmWhite, alpha: c.a)]
            let n = SCNNode(geometry: disc)
            n.position = SCNVector3(0, Float(pillarH), 0)
            root.addChildNode(n)
        }

        // ── Particle System — Ice Crystal Shimmer ───────────────
        // Tiny bright particles drifting slowly upward inside the
        // pillar, simulating the suspended ice crystals that cause
        // real light pillars. Additive blend so they look like
        // tiny points of reflected light, not solid dots.
        let particles = SCNParticleSystem()
        particles.particleLifeSpan = 3.0
        particles.particleLifeSpanVariation = 1.5
        particles.birthRate = 20
        particles.warmupDuration = 2.0
        particles.emissionDuration = .greatestFiniteMagnitude

        particles.particleSize = 0.005
        particles.particleSizeVariation = 0.003
        particles.particleColor = warmWhite
        particles.particleColorVariation = SCNVector4(0, 0, 0.05, 0)
        particles.blendMode = .additive

        let emitterShape = SCNCylinder(radius: 0.025, height: pillarH * 0.9)
        particles.emitterShape = emitterShape
        particles.birthLocation = .volume

        particles.particleVelocity = 0.04
        particles.particleVelocityVariation = 0.025
        particles.emittingDirection = SCNVector3(0, 1, 0)
        particles.spreadingAngle = 8

        // Fade in and out so particles appear/disappear smoothly
        let fadeIn = SCNParticlePropertyController(
            animation: {
                let anim = CAKeyframeAnimation()
                anim.values = [0.0, 1.0, 1.0, 0.0]
                anim.keyTimes = [0, 0.15, 0.8, 1.0]
                anim.duration = 1.0
                return anim
            }()
        )
        particles.propertyControllers = [.opacity: fadeIn]

        let particleNode = SCNNode()
        particleNode.position = SCNVector3(0, Float(pillarH * 0.45), 0)
        particleNode.addParticleSystem(particles)
        root.addChildNode(particleNode)

        // ── Grow Animation ──────────────────────────────────────
        root.scale = SCNVector3(1, 0.001, 1)
        scene.rootNode.addChildNode(root)
        pinNodes[pin.id] = root

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.9
        SCNTransaction.animationTimingFunction =
            CAMediaTimingFunction(name: .easeOut)
        root.scale = SCNVector3(1, 1, 1)
        SCNTransaction.commit()

        addPinDistanceLabel(pin: pin)
    }

    private func addPinDistanceLabel(pin: MapPin) {
        guard let scene = scnView?.scene else { return }

        let textGeom = SCNText(string: pin.label + "\n– m", extrusionDepth: 0)
        textGeom.font = UIFont.systemFont(ofSize: 0.14, weight: .bold)
        textGeom.flatness = 0.005
        textGeom.alignmentMode = CATextLayerAlignmentMode.center.rawValue

        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.clear
        mat.emission.contents = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1.0)
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.isDoubleSided = true
        textGeom.materials = [mat]

        let node = SCNNode(geometry: textGeom)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2, 0, 0)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.position = SCNVector3(pin.position.x, pin.position.y + 0.9, pin.position.z)

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

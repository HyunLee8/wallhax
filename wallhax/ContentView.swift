import SwiftUI
import Combine
import RealityKit
import ARKit

// MARK: - Main Content View

struct ContentView: View {
    let useCase: UseCase
    let onExit: () -> Void

    @StateObject private var arState = ARState.shared
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
            ARViewContainer(isRecording: $isRecording)
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

                        MinimapView(
                            trajectory: arState.trajectory,
                            currentPos: SIMD2<Float>(arState.position.x, arState.position.z),
                            heading: arState.heading,
                            pins: arState.pins,
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
            if showPinWheel {
                PinWheelOverlay(
                    labels: useCase.pinLabels,
                    accentColor: accentColor,
                    selectedIndex: selectedPinIndex
                )
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .zIndex(15)
            }

            // ── Full map overlay ─────────────────────────────────
            if showFullMap {
                FullMapView(
                    trajectory: arState.trajectory,
                    currentPos: SIMD2<Float>(arState.position.x, arState.position.z),
                    heading: arState.heading,
                    pins: arState.pins,
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

                var files: [(relativePath: String, data: Data)] = []
                while let fileURL = enumerator.nextObject() as? URL {
                    guard fileURL.isFileURL, !fileURL.hasDirectoryPath else { continue }
                    let filePath = fileURL.standardizedFileURL.path
                    let basePath = sessionURL.standardizedFileURL.path + "/"
                    let relativePath = filePath.hasPrefix(basePath)
                        ? String(filePath.dropFirst(basePath.count))
                        : fileURL.lastPathComponent
                    if let data = try? Data(contentsOf: fileURL) {
                        files.append((relativePath: relativePath, data: data))
                    }
                }

                let sock = try Self.createTCPSocket(host: serverIP, port: serverPort)

                try Self.sendPacket(sock: sock, data: NetworkingManager.shared.missionId.data(using: .utf8)!)
                try Self.sendPacket(sock: sock, data: NetworkingManager.shared.clientId.data(using: .utf8)!)

                let countStr = "\(files.count)"
                try Self.sendPacket(sock: sock, data: countStr.data(using: .utf8)!)

                for (i, file) in files.enumerated() {
                    DispatchQueue.main.async {
                        sendStatus = "Sending \(i + 1)/\(files.count)..."
                    }
                    try Self.sendPacket(sock: sock, data: file.relativePath.data(using: .utf8)!)
                    try Self.sendPacket(sock: sock, data: file.data)
                }

                close(sock)
                try? FileManager.default.removeItem(at: sessionURL)

                DispatchQueue.main.async {
                    sendStatus = "Sent \(files.count) files ✓"
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

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView

        let peersAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(peersAnchor)
        context.coordinator.peersAnchor = peersAnchor

        let coordinator = context.coordinator

        NetworkingManager.shared.onPeerTransformReceived = { [weak coordinator] peerId, transform in
            coordinator?.updatePeer(peerId, transform: transform)
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

        let configuration = ARWorldTrackingConfiguration()
        
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            arView.debugOptions.insert(.showSceneUnderstanding)
        }
        
        if let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "Origin Reference Images", bundle: nil) {
            configuration.detectionImages = referenceImages
        }

        arView.session.run(configuration)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - AR Session Coordinator

class Coordinator: NSObject, ARSessionDelegate {
    weak var arView: ARView?
    @Binding var isRecording: Bool
    var peersAnchor: AnchorEntity?
    var peerEntities: [String: ModelEntity] = [:]
    var pinAnchors: [UUID: AnchorEntity] = [:]
    var pinBobEntities: [UUID: (entity: Entity, phase: Float)] = [:]
    var subscriptions: [Any] = []

    init(isRecording: Binding<Bool>) {
        _isRecording = isRecording
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
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
            session.setWorldOrigin(relativeTransform: anchor.transform)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        NetworkingManager.shared.processFrame(frame)
        ARState.shared.update(frame: frame)
        if isRecording {
            SnapshotManager.shared.processFrame(frame)
        }
    }

    // MARK: - Peer Avatars

    func updatePeer(_ peerId: String, transform: simd_float4x4) {
        guard let anchor = peersAnchor else { return }

        if peerEntities[peerId] == nil {
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 0.05),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            anchor.addChild(sphere)
            peerEntities[peerId] = sphere
        }
        peerEntities[peerId]!.transform = Transform(matrix: transform)
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

        let anchor = AnchorEntity(world: pin.position)

        let pinRoot = Entity()
        pinRoot.position = [0, 0.65, 0]

        let pinBob = Entity()

        let head = makeHead(for: pin.label, color: color)
        let stem = makeStem(color: color)
        pinBob.addChild(head)
        pinBob.addChild(stem)
        pinRoot.addChild(pinBob)
        anchor.addChild(pinRoot)
        arView.scene.addAnchor(anchor)
        pinAnchors[pin.id] = anchor

        let pinId = pin.id
        let phase = Float(abs(pin.id.hashValue) % 1000) / 1000.0 * 2 * Float.pi

        // 1. Drop from above
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            pinRoot.move(to: Transform(translation: .zero),
                         relativeTo: anchor,
                         duration: 0.48,
                         timingFunction: .easeIn)
        }

        // 2. Squish–bounce on landing
        let headRestRotation = head.transform.rotation
        let headRestTranslation = head.position

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            head.move(to: Transform(scale: SIMD3(1.35, 0.52, 1.35),
                                    rotation: headRestRotation,
                                    translation: headRestTranslation),
                      relativeTo: pinBob, duration: 0.09, timingFunction: .easeOut)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                head.move(to: Transform(scale: SIMD3(0.86, 1.24, 0.86),
                                        rotation: headRestRotation,
                                        translation: headRestTranslation),
                          relativeTo: pinBob, duration: 0.11, timingFunction: .easeOut)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                    head.move(to: Transform(scale: .one,
                                            rotation: headRestRotation,
                                            translation: headRestTranslation),
                              relativeTo: pinBob, duration: 0.13, timingFunction: .easeInOut)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        self.pinBobEntities[pinId] = (entity: pinBob, phase: phase)
                    }
                }
            }
        }
    }

    // MARK: - Pin Head Shapes

    private func makeHead(for label: String, color: UIColor) -> ModelEntity {
        var mat = SimpleMaterial(color: color, isMetallic: true)
        mat.roughness = .float(0.18)
        let l = label.lowercased()

        if l == "objective" || l == "victim" {
            let e = ModelEntity(mesh: .generateSphere(radius: 0.048), materials: [mat])
            e.position = [0, 0.048, 0]
            return e
        }
        if l == "command" {
            let e = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.056, 0.056, 0.056)),
                                materials: [mat])
            e.transform = Transform(scale: .one,
                                    rotation: simd_quatf(angle: .pi / 4, axis: [0, 1, 0]),
                                    translation: [0, 0.028, 0])
            return e
        }
        if l == "threat" || l == "fire" {
            let e = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.046, 0.046, 0.046)),
                                materials: [mat])
            e.transform = Transform(scale: .one,
                                    rotation: simd_quatf(angle: .pi / 4, axis: [0, 1, 0]),
                                    translation: [0, 0.023, 0])
            return e
        }
        if l == "hazard" {
            let e = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.038, 0.038, 0.038)),
                                materials: [mat])
            e.position = [0, 0.019, 0]
            return e
        }
        if l == "rally" || l == "clear" || l == "hydrant" {
            let e = ModelEntity(mesh: .generateSphere(radius: 0.032), materials: [mat])
            e.position = [0, 0.032, 0]
            return e
        }
        if l == "entry" || l == "found" {
            let e = ModelEntity(
                mesh: .generateBox(width: 0.065, height: 0.013, depth: 0.065),
                materials: [mat])
            e.position = [0, 0.0065, 0]
            return e
        }
        if l == "cover" || l == "exit" {
            let e = ModelEntity(
                mesh: .generateBox(width: 0.065, height: 0.013, depth: 0.065),
                materials: [mat])
            e.transform = Transform(scale: .one,
                                    rotation: simd_quatf(angle: .pi / 4, axis: [0, 1, 0]),
                                    translation: [0, 0.0065, 0])
            return e
        }
        if l == "checkpoint" {
            let e = ModelEntity(
                mesh: .generateBox(width: 0.014, height: 0.068, depth: 0.014),
                materials: [mat])
            e.position = [0, 0.034, 0]
            return e
        }
        if l == "observation" || l == "medical" {
            let e = ModelEntity(mesh: .generateSphere(radius: 0.024), materials: [mat])
            e.position = [0, 0.024, 0]
            return e
        }
        let e = ModelEntity(mesh: .generateSphere(radius: 0.032), materials: [mat])
        e.position = [0, 0.032, 0]
        return e
    }

    private func makeStem(color: UIColor) -> ModelEntity {
        var mat = SimpleMaterial(color: color.withAlphaComponent(0.55), isMetallic: false)
        mat.roughness = .float(0.6)
        let e = ModelEntity(
            mesh: .generateBox(width: 0.005, height: 0.09, depth: 0.005),
            materials: [mat])
        e.position = [0, -0.045, 0]
        return e
    }

    // MARK: - Idle Bob Animation

    func updatePinBobbing() {
        let time = Float(CACurrentMediaTime())
        for item in pinBobEntities.values {
            item.entity.position.y = sin(time * 1.8 + item.phase) * 0.008
        }
    }
}

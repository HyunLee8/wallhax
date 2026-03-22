import ARKit
import Combine
import SwiftUI

private let peerTimeout: TimeInterval = 3.0
private let wallRefreshInterval: TimeInterval = 30.0

struct HFloor {
    let center: SIMD3<Float>
    let widthX: Float
    let depthZ: Float
    let xDirXZ: SIMD2<Float>  // unit vector: local X axis projected onto world XZ
}

struct Wall3D {
    let center: SIMD3<Float>
    let width: Float           // extent along local X (horizontal along wall surface)
    let height: Float          // extent along local Z (vertical for vertical planes)
    let xDirXZ: SIMD2<Float>   // unit vector: local X direction in world XZ
}

struct PeerMapState {
    var trajectory: [simd_float4x4]
    var heading: Float
    var lastSeen: Date
    var callsign: String = ""
}

class ARState: ObservableObject {
    static let shared = ARState()

    @Published var position: SIMD3<Float> = .zero
    @Published var heading: Float = 0
    @Published var trackingState: String = "initializing"
    @Published var featureCount: Int = 0
    @Published var trajectory: [simd_float4x4] = []
    @Published var pins: [MapPin] = []
    @Published var distanceWalked: Float = 0
    @Published var isRelayConnected: Bool = NetworkingManager.shared.serverDiscovered
    @Published var isTCPConnected: Bool = NetworkingManager.shared.tcpConnected
    @Published var peers: [String: PeerMapState] = [:]
    @Published var walls: [Wall3D] = []
    @Published var floors: [HFloor] = []
    @Published var originLocked: Bool = false

    private var lastPosition: SIMD3<Float>?
    private var lastTrajectoryPosition: SIMD3<Float>?
    private var pruneTimer: Timer?
    private var wallRefreshTimer: Timer?
    private var wallsByClient: [String: [Wall3D]] = [:]
    private var floorsByClient: [String: [HFloor]] = [:]

    private init() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pruneStalePeers()
        }

        NetworkingManager.shared.onTCPConnectionChanged = { [weak self] connected in
            DispatchQueue.main.async { self?.isTCPConnected = connected }
            guard connected else { return }
            NetworkingManager.shared.sendGetPlanes()
        }

        NetworkingManager.shared.onAllWallsReceived = { [weak self] planes in
            self?.setAllWalls(from: planes)
        }

        NetworkingManager.shared.onPeerWallsReceived = { [weak self] clientId, planes in
            self?.updatePeerWalls(clientId: clientId, from: planes)
        }

        wallRefreshTimer = Timer.scheduledTimer(withTimeInterval: wallRefreshInterval, repeats: true) { [weak self] _ in
            guard NetworkingManager.shared.tcpConnected else { return }
            NetworkingManager.shared.sendGetPlanes()
        }
    }

    private func setAllWalls(from planes: [[String: Any]]) {
        updatePlanes(clientId: "__sync__", from: planes)
    }

    private func updatePeerWalls(clientId: String, from planes: [[String: Any]]) {
        updatePlanes(clientId: clientId, from: planes)
    }

    func updateLocalPlanes(_ planes: [[String: Any]]) {
        updatePlanes(clientId: "__local__", from: planes)
    }

    private func updatePlanes(clientId: String, from planes: [[String: Any]]) {
        wallsByClient[clientId]  = wall3DSegments(from: planes)
        floorsByClient[clientId] = floorSegments(from: planes)
        walls  = wallsByClient.values.flatMap { $0 }
        floors = floorsByClient.values.flatMap { $0 }
    }

    private func wall3DSegments(from planes: [[String: Any]]) -> [Wall3D] {
        planes.compactMap { plane in
            guard plane["alignment"] as? String == "vertical",
                  let center = plane["center"] as? [NSNumber], center.count == 3,
                  let extent = plane["extent"] as? [NSNumber], extent.count == 2,
                  let transform = plane["transform"] as? [NSNumber], transform.count == 16
            else { return nil }

            let f = transform.map { $0.floatValue }
            let axisXZ = SIMD2<Float>(f[0], f[2])
            let axisLen = simd_length(axisXZ)
            guard axisLen > 0.001 else { return nil }

            return Wall3D(
                center: SIMD3<Float>(center[0].floatValue, center[1].floatValue, center[2].floatValue),
                width: extent[0].floatValue,
                height: extent[1].floatValue,
                xDirXZ: axisXZ / axisLen
            )
        }
    }

    private func floorSegments(from planes: [[String: Any]]) -> [HFloor] {
        planes.compactMap { plane in
            guard plane["alignment"] as? String == "horizontal",
                  let center = plane["center"] as? [NSNumber], center.count == 3,
                  let extent = plane["extent"] as? [NSNumber], extent.count == 2,
                  let transform = plane["transform"] as? [NSNumber], transform.count == 16
            else { return nil }

            let f = transform.map { $0.floatValue }
            let xDirXZ = SIMD2<Float>(f[0], f[2])
            let axisLen = simd_length(xDirXZ)
            guard axisLen > 0.001 else { return nil }

            return HFloor(
                center: SIMD3<Float>(center[0].floatValue, center[1].floatValue, center[2].floatValue),
                widthX: extent[0].floatValue,
                depthZ: extent[1].floatValue,
                xDirXZ: xDirXZ / axisLen
            )
        }
    }


    private func pruneStalePeers() {
        let cutoff = Date().addingTimeInterval(-peerTimeout)
        let stale = peers.keys.filter { peers[$0]!.lastSeen < cutoff }
        guard !stale.isEmpty else { return }
        for id in stale { peers.removeValue(forKey: id) }
    }

    func update(frame: ARFrame) {
        let t = frame.camera.transform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        let yaw = atan2(-t.columns.2.x, -t.columns.2.z)

        if let last = lastPosition {
            let d = simd_distance(pos, last)
            if d > 0.01 && d < 2.0 {
                distanceWalked += d
            }
        }
        lastPosition = pos

        DispatchQueue.main.async {
            self.position = pos
            self.heading = yaw
            self.featureCount = frame.rawFeaturePoints?.points.count ?? 0

            let shouldAppend = self.lastTrajectoryPosition.map { simd_distance(pos, $0) >= 0.05 } ?? true
            if shouldAppend {
                self.trajectory.append(t)
                self.lastTrajectoryPosition = pos
                if self.trajectory.count > 3000 {
                    self.trajectory = Array(self.trajectory.suffix(2000))
                }
            }

            switch frame.camera.trackingState {
            case .normal: self.trackingState = "normal"
            case .limited(let r):
                switch r {
                case .initializing:         self.trackingState = "initializing"
                case .excessiveMotion:      self.trackingState = "slow down"
                case .insufficientFeatures: self.trackingState = "need features"
                case .relocalizing:         self.trackingState = "relocalizing"
                @unknown default:           self.trackingState = "limited"
                }
            case .notAvailable: self.trackingState = "unavailable"
            }
        }
    }

    var onPinAdded: ((MapPin, UIColor) -> Void)?
    var requestDropPin: ((String, UIColor) -> Void)?

    func addPin(label: String, color: UIColor = .white) {
        addPin(position: position, label: label, color: color)
    }

    func addPin(position: SIMD3<Float>, label: String, color: UIColor = .white) {
        let pin = MapPin(
            position: position,
            position2D: SIMD2<Float>(position.x, position.z),
            label: label,
            timestamp: Date()
        )
        DispatchQueue.main.async {
            self.pins.append(pin)
            self.onPinAdded?(pin, color)
        }
    }

    func updatePeer(_ peerId: String, transform: simd_float4x4, callsign: String = "") {
        let pos2D = SIMD2<Float>(transform.columns.3.x, transform.columns.3.z)
        let yaw = atan2(-transform.columns.2.x, -transform.columns.2.z)
        DispatchQueue.main.async {
            var state = self.peers[peerId] ?? PeerMapState(trajectory: [], heading: 0, lastSeen: Date())
            if !callsign.isEmpty { state.callsign = callsign }
            state.lastSeen = Date()
            if let last = state.trajectory.last {
                let lastPos2D = SIMD2<Float>(last.columns.3.x, last.columns.3.z)
                if simd_distance(pos2D, lastPos2D) <= 0.01 {
                    state.heading = yaw
                    self.peers[peerId] = state
                    return
                }
            }
            state.trajectory.append(transform)
            if state.trajectory.count > 3000 {
                state.trajectory = Array(state.trajectory.suffix(2000))
            }
            state.heading = yaw
            self.peers[peerId] = state
        }
    }

    func reset() {
        DispatchQueue.main.async {
            self.position = .zero
            self.heading = 0
            self.trackingState = "initializing"
            self.featureCount = 0
            self.trajectory = []
            self.pins = []
            self.peers = [:]
            self.walls = []
            self.floors = []
            self.wallsByClient = [:]
            self.floorsByClient = [:]
            self.distanceWalked = 0
            self.originLocked = false
            self.lastPosition = nil
            self.lastTrajectoryPosition = nil
        }
    }
}

//  Mapping module — streams camera pose + sparse point cloud over UDP,
//  and receives peer poses forwarded by the relay server.

import Foundation
import ARKit

class NetworkingManager {

    static let shared = NetworkingManager()

    let clientId = UUID().uuidString

    // Set to override broadcast discovery with a fixed server IP
    private let staticServerIP: String? = "172.25.138.15"

    private var udpSocket: Int32 = -1
    private var serverAddr: sockaddr_in
    private let serverPort: UInt16 = 9876
    private let localPort: UInt16 = 9877

    private(set) var serverDiscovered = false
    private let serverAddrLock = NSLock()
    private(set) var missionId: String = "unknown"

    // Throttle: process every N frames (ARKit runs at 60fps, we don't need all of them)
    private var frameCount = 0
    private let sendEveryN = 3  // ~20 updates/sec

    // Point cloud accumulation
    private var collectedPoints: Set<PointKey> = []
    private var isCollecting = false

    private let peerLock = NSLock()
    private(set) var peerTransforms: [String: simd_float4x4] = [:]
    var onPeersUpdated: (([String: simd_float4x4]) -> Void)?
    var onPinReceived: ((SIMD3<Float>, String) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private init() {
        serverAddr = sockaddr_in()
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = serverPort.bigEndian
        if let ip = staticServerIP {
            serverAddr.sin_addr.s_addr = inet_addr(ip)
            serverDiscovered = true
        } else {
            serverAddr.sin_addr.s_addr = INADDR_BROADCAST
        }

        udpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard udpSocket >= 0 else {
            print("[NetworkingManager] socket() failed: \(String(cString: strerror(errno)))")
            return
        }
        print("[NetworkingManager] socket fd=\(udpSocket)")

        var broadcastEnable: Int32 = 1
        let sockoptResult = setsockopt(udpSocket, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        if sockoptResult < 0 {
            print("[NetworkingManager] setsockopt(SO_BROADCAST) failed: \(String(cString: strerror(errno)))")
        } else {
            print("[NetworkingManager] SO_BROADCAST enabled")
        }

        var localAddr = sockaddr_in()
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_port = localPort.bigEndian
        localAddr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(udpSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            print("[NetworkingManager] bind(::\(localPort)) failed: \(String(cString: strerror(errno)))")
            return
        }
        print("[NetworkingManager] bound to :\(localPort), client_id=\(clientId.prefix(8))")

        startReceiveLoop()
        if staticServerIP == nil {
            sendDiscovery()
        } else {
            print("[NetworkingManager] using static server IP: \(staticServerIP!)")
        }
    }

    func getServerIP() -> String { staticServerIP ?? "" }

    func processFrame(_ frame: ARFrame) {
        frameCount += 1

        guard serverDiscovered else {
            if frameCount % 90 == 1 {
                print("[NetworkingManager] still discovering... (frame \(frameCount))")
                sendDiscovery()
            }
            return
        }

        guard frameCount % sendEveryN == 0 else { return }

        let t = frame.camera.transform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        let matrix: [Float] = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
        ]

        if isCollecting, let features = frame.rawFeaturePoints {
            for p in features.points {
                collectedPoints.insert(PointKey(p))
            }
        }

        let originDetected = frame.anchors.contains(where: { $0 is ARImageAnchor })

        let payload: [String: Any] = [
            "client_id": clientId,
            "timestamp": frame.timestamp,
            "position": [position.x, position.y, position.z],
            "transform": matrix,
            "origin_locked": originDetected,
            "tracking_state": trackingStateString(frame.camera.trackingState)
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendUDP(jsonString)
        }
    }

    private func sendDiscovery() {
        let result = sendUDP("{\"type\":\"discover\",\"client_id\":\"\(clientId)\"}")
        print("[NetworkingManager] sendDiscovery → sent=\(result) bytes to broadcast:\(serverPort)")
    }

    private func startReceiveLoop() {
        DispatchQueue(label: "com.wallhax.udp.receive", qos: .background).async { [weak self] in
            guard let self else { return }
            print("[NetworkingManager] receive loop started")
            var buffer = [UInt8](repeating: 0, count: 65536)
            var srcAddr = sockaddr_in()

            while true {
                var srcAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &srcAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        recvfrom(self.udpSocket, &buffer, buffer.count, 0, sockPtr, &srcAddrLen)
                    }
                }
                guard n > 0 else {
                    print("[NetworkingManager] recvfrom error: \(String(cString: strerror(errno)))")
                    continue
                }

                let data = Data(bytes: buffer, count: n)
                guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                if let type_ = payload["type"] as? String, type_ == "hello" {
                    self.serverAddrLock.lock()
                    self.serverAddr = srcAddr
                    self.serverAddr.sin_port = self.serverPort.bigEndian
                    self.serverDiscovered = true
                    self.serverAddrLock.unlock()

                    if let mid = payload["mission_id"] as? String {
                        self.missionId = mid
                    }

                    let ip = String(cString: inet_ntoa(srcAddr.sin_addr))
                    print("[NetworkingManager] server discovered at \(ip):\(self.serverPort), mission=\(self.missionId.prefix(8))")
                    DispatchQueue.main.async { self.onConnectionChanged?(true) }
                    continue
                }

                if let type_ = payload["type"] as? String, type_ == "pin",
                   let posArray = payload["position"] as? [NSNumber], posArray.count == 3,
                   let label = payload["label"] as? String {
                    let position = SIMD3<Float>(posArray[0].floatValue, posArray[1].floatValue, posArray[2].floatValue)
                    DispatchQueue.main.async {
                        self.onPinReceived?(position, label)
                    }
                    continue
                }

                guard
                    let peerId = payload["client_id"] as? String,
                    peerId != self.clientId,
                    let transformArray = payload["transform"] as? [NSNumber],
                    transformArray.count == 16
                else { continue }

                let f = transformArray.map { $0.floatValue }
                let matrix = simd_float4x4(
                    SIMD4<Float>(f[0],  f[1],  f[2],  f[3]),
                    SIMD4<Float>(f[4],  f[5],  f[6],  f[7]),
                    SIMD4<Float>(f[8],  f[9],  f[10], f[11]),
                    SIMD4<Float>(f[12], f[13], f[14], f[15])
                )

                self.peerLock.lock()
                self.peerTransforms[peerId] = matrix
                let snapshot = self.peerTransforms
                self.peerLock.unlock()

                DispatchQueue.main.async {
                    self.onPeersUpdated?(snapshot)
                }
            }
        }
    }

    @discardableResult
    private func sendUDP(_ message: String) -> Int {
        guard udpSocket >= 0 else { return -1 }

        let data = Array(message.utf8)
        serverAddrLock.lock()
        var addr = serverAddr
        serverAddrLock.unlock()

        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                let n = sendto(udpSocket, data, data.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                if n < 0 {
                    print("[NetworkingManager] sendto failed: \(String(cString: strerror(errno)))")
                }
                return Int(n)
            }
        }
    }

    private func trackingStateString(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .notAvailable: return "not_available"
        case .limited(let reason):
            switch reason {
            case .initializing: return "initializing"
            case .excessiveMotion: return "excessive_motion"
            case .insufficientFeatures: return "insufficient_features"
            case .relocalizing: return "relocalizing"
            @unknown default: return "limited_unknown"
            }
        case .normal: return "normal"
        }
    }

    func sendPin(position: SIMD3<Float>, label: String) {
        let payload: [String: Any] = [
            "type": "pin",
            "client_id": clientId,
            "position": [position.x, position.y, position.z],
            "label": label
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendUDP(jsonString)
        }
    }

    func startCollection() {
        collectedPoints = []
        isCollecting = true
    }

    func stopCollection() -> [[Float]] {
        isCollecting = false
        let points = collectedPoints.map { [$0.x, $0.y, $0.z] }
        collectedPoints = []
        return points
    }

    deinit {
        if udpSocket >= 0 {
            close(udpSocket)
        }
    }
}

// Deduplicated point key rounded to 1cm precision
private struct PointKey: Hashable {
    let x: Float
    let y: Float
    let z: Float

    init(_ p: SIMD3<Float>) {
        x = (p.x * 100).rounded() / 100
        y = (p.y * 100).rounded() / 100
        z = (p.z * 100).rounded() / 100
    }
}

//  Streams camera pose over UDP and receives peer poses + events forwarded by the relay server.

import Foundation
import ARKit
import simd

class NetworkingManager {

    static let shared = NetworkingManager()

    let clientId = UUID().uuidString

    // Set to override broadcast discovery with a fixed server IP
    #if DEBUG
    private let staticServerIP: String? = "172.25.146.41"  // local dev Mac
    #else
    private let staticServerIP: String? = "172.25.138.15"  // ops Mac
    #endif

    private var udpSocket: Int32 = -1
    private var serverAddr: sockaddr_in
    private let serverPort: UInt16 = 9876
    private let localPort: UInt16 = 9877
    private let tcpEventPort: UInt16 = 9878

    private(set) var serverDiscovered = false
    private let serverAddrLock = NSLock()
    private(set) var missionId: String = "unknown"

    private var tcpSocket: Int32 = -1
    private let tcpSocketLock = NSLock()
    private(set) var tcpConnected = false
    private var tcpReconnecting = false

    // Throttle: send every N frames (ARKit runs at 60fps)
    private var frameCount = 0
    private let sendEveryN = 3  // ~20 updates/sec

    // MARK: - Events

    var onPeerTransformReceived: ((String, simd_float4x4) -> Void)?
    var onPinReceived: ((SIMD3<Float>, String) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onTCPConnectionChanged: ((Bool) -> Void)?
    var onAllWallsReceived: (([[String: Any]]) -> Void)?
    var onPeerWallsReceived: ((String, [[String: Any]]) -> Void)?

    // MARK: - Init

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
            DispatchQueue.global(qos: .background).async { [weak self] in self?.connectTCP() }
        }
    }

    func getServerIP() -> String { staticServerIP ?? "" }

    // MARK: - Outbound

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

        // Extract all values from the frame immediately so ARKit can release it.
        let t = frame.camera.transform
        let timestamp = frame.timestamp
        let trackingState = trackingStateString(frame.camera.trackingState)
        let originDetected = frame.anchors.contains(where: { $0 is ARImageAnchor })

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let matrix: [Float] = [
                t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
                t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
                t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
                t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
            ]
            let payload: [String: Any] = [
                "client_id": self.clientId,
                "timestamp": timestamp,
                "position": [position.x, position.y, position.z],
                "transform": matrix,
                "origin_locked": originDetected,
                "tracking_state": trackingState
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.sendUDP(jsonString)
            }
        }
    }

    func sendGetPlanes() {
        sendTCPMessage(["type": "get_planes", "client_id": clientId])
    }

    func sendPlanes(_ planes: [[String: Any]]) {
        sendTCPMessage([
            "type": "planes",
            "client_id": clientId,
            "planes": planes
        ])
    }

    func sendPin(position: SIMD3<Float>, label: String) {
        sendTCPMessage([
            "type": "pin",
            "client_id": clientId,
            "position": [position.x, position.y, position.z],
            "label": label
        ])
    }

    func sendToMac(sessionPath: String, onStatusUpdate: @escaping (Bool, Bool, String) -> Void) {
        onStatusUpdate(false, false, "Connecting...")

        DispatchQueue.global(qos: .userInitiated).async {
            let serverPort: UInt16 = 9877

            do {
                let sock = try Self.createTCPSocket(host: NetworkingManager.shared.getServerIP(), port: serverPort)
                let sessionURL = URL(fileURLWithPath: sessionPath)
                let fm = FileManager.default

                guard let enumerator = fm.enumerator(at: sessionURL, includingPropertiesForKeys: nil) else {
                    DispatchQueue.main.async { onStatusUpdate(true, false, "Failed to read scan folder") }
                    return
                }

                // Collect file URLs without loading data into memory
                var fileURLs: [(relativePath: String, url: URL)] = []
                while let fileURL = enumerator.nextObject() as? URL {
                    guard fileURL.isFileURL, !fileURL.hasDirectoryPath else { continue }
                    let filePath = fileURL.standardizedFileURL.path
                    let basePath = sessionURL.standardizedFileURL.path + "/"
                    let relativePath = filePath.hasPrefix(basePath)
                        ? String(filePath.dropFirst(basePath.count))
                        : fileURL.lastPathComponent
                    fileURLs.append((relativePath: relativePath, url: fileURL))
                }

                try Self.sendPacket(sock: sock, data: NetworkingManager.shared.missionId.data(using: .utf8)!)
                try Self.sendPacket(sock: sock, data: NetworkingManager.shared.clientId.data(using: .utf8)!)
                try Self.sendPacket(sock: sock, data: "\(fileURLs.count)".data(using: .utf8)!)

                // Stream one file at a time — never hold more than one in memory
                for (i, file) in fileURLs.enumerated() {
                    DispatchQueue.main.async { onStatusUpdate(false, false, "Sending \(i + 1)/\(fileURLs.count)...") }
                    guard let data = try? Data(contentsOf: file.url) else { continue }
                    try Self.sendPacket(sock: sock, data: file.relativePath.data(using: .utf8)!)
                    try Self.sendPacket(sock: sock, data: data)
                }

                close(sock)
                DispatchQueue.main.async { onStatusUpdate(true, true, "Sent \(fileURLs.count) files ✓") }

            } catch {
                DispatchQueue.main.async { onStatusUpdate(true, false, "Send failed: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: - UDP

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
                let bufferCount = buffer.count
                let n = withUnsafeMutablePointer(to: &srcAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        recvfrom(self.udpSocket, &buffer, bufferCount, 0, sockPtr, &srcAddrLen)
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
                    DispatchQueue.global(qos: .background).async { self.connectTCP() }
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

                DispatchQueue.main.async {
                    self.onPeerTransformReceived?(peerId, matrix)
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

    // MARK: - TCP Events

    private func connectTCP() {
        guard serverDiscovered else { return }
        let newSock = (try? Self.createTCPSocket(host: getServerIP(), port: tcpEventPort)) ?? -1
        tcpSocketLock.lock()
        if tcpSocket >= 0 { close(tcpSocket) }
        tcpSocket = newSock
        tcpSocketLock.unlock()
        let connected = newSock >= 0
        guard connected != tcpConnected else { return }
        tcpConnected = connected
        print("[NetworkingManager] TCP event socket \(connected ? "connected" : "failed")")
        DispatchQueue.main.async { self.onTCPConnectionChanged?(connected) }
        if connected { startTCPReceiveLoop(sock: newSock) }
    }

    private func startTCPReceiveLoop(sock: Int32) {
        DispatchQueue(label: "com.wallhax.tcp.receive", qos: .background).async { [weak self] in
            guard let self else { return }
            print("[NetworkingManager] TCP receive loop started (fd=\(sock))")
            while true {
                guard let data = try? Self.recvPacket(sock: sock),
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    self.tcpSocketLock.lock()
                    if self.tcpSocket == sock { close(self.tcpSocket); self.tcpSocket = -1 }
                    self.tcpSocketLock.unlock()
                    guard self.tcpConnected else { return }
                    self.tcpConnected = false
                    print("[NetworkingManager] TCP receive loop ended (fd=\(sock))")
                    DispatchQueue.main.async { self.onTCPConnectionChanged?(false) }
                    self.reconnectTCPInBackground()
                    return
                }

                switch payload["type"] as? String {
                case "pin":
                    if let posArray = payload["position"] as? [NSNumber], posArray.count == 3,
                       let label = payload["label"] as? String {
                        let position = SIMD3<Float>(posArray[0].floatValue, posArray[1].floatValue, posArray[2].floatValue)
                        DispatchQueue.main.async { self.onPinReceived?(position, label) }
                    }
                case "planes_all":
                    if let planes = payload["planes"] as? [[String: Any]] {
                        DispatchQueue.main.async { self.onAllWallsReceived?(planes) }
                    }
                case "planes":
                    if let planes = payload["planes"] as? [[String: Any]],
                       let peerId = payload["client_id"] as? String, peerId != self.clientId {
                        DispatchQueue.main.async { self.onPeerWallsReceived?(peerId, planes) }
                    }
                default:
                    break
                }
            }
        }
    }

    private func reconnectTCPInBackground() {
        guard !tcpReconnecting else { return }
        tcpReconnecting = true
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.connectTCP()
            self.tcpReconnecting = false
            if !self.tcpConnected { self.reconnectTCPInBackground() }
        }
    }

    func sendTCPMessage(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        tcpSocketLock.lock()
        let sock = tcpSocket
        tcpSocketLock.unlock()
        guard sock >= 0 else { return }
        // Send errors are handled by the receive loop detecting the closed connection
        try? Self.sendPacket(sock: sock, data: data)
    }

    // MARK: - TCP Helpers

    private static func recvExact(sock: Int32, buffer: inout [UInt8]) throws {
        var received = 0
        let total = buffer.count
        while received < total {
            let n = buffer.withUnsafeMutableBufferPointer { ptr in
                recv(sock, ptr.baseAddress! + received, total - received, 0)
            }
            guard n > 0 else {
                throw NSError(domain: "recv", code: 5, userInfo: [NSLocalizedDescriptionKey: "Connection closed"])
            }
            received += n
        }
    }

    private static func recvPacket(sock: Int32) throws -> Data {
        var lengthBytes = [UInt8](repeating: 0, count: 4)
        try recvExact(sock: sock, buffer: &lengthBytes)
        let length = Int(UInt32(bigEndian: lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self) }))
        var dataBytes = [UInt8](repeating: 0, count: length)
        try recvExact(sock: sock, buffer: &dataBytes)
        return Data(dataBytes)
    }

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

    deinit {
        if udpSocket >= 0 { close(udpSocket) }
        if tcpSocket >= 0 { close(tcpSocket) }
    }
}

import ARKit
import Combine
import SwiftUI

class ARState: ObservableObject {
    static let shared = ARState()

    @Published var position: SIMD3<Float> = .zero
    @Published var heading: Float = 0
    @Published var trackingState: String = "initializing"
    @Published var featureCount: Int = 0
    @Published var trajectory: [SIMD2<Float>] = []
    @Published var pins: [MapPin] = []
    @Published var distanceWalked: Float = 0
    @Published var isRelayConnected: Bool = NetworkingManager.shared.serverDiscovered

    private var lastPosition: SIMD3<Float>?

    func update(frame: ARFrame) {
        let t = frame.camera.transform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        let forward = SIMD3<Float>(t.columns.2.x, 0, t.columns.2.z)
        let yaw = atan2(forward.x, forward.z)

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
            self.trajectory.append(SIMD2<Float>(pos.x, pos.z))

            if self.trajectory.count > 3000 {
                self.trajectory = Array(self.trajectory.suffix(2000))
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

    func reset() {
        DispatchQueue.main.async {
            self.position = .zero
            self.heading = 0
            self.trackingState = "initializing"
            self.featureCount = 0
            self.trajectory = []
            self.pins = []
            self.distanceWalked = 0
            self.lastPosition = nil
        }
    }
}

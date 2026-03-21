import SwiftUI
import ARKit
import RealityKit

struct MarkerScanView: View {
    let useCase: UseCase
    let onDetected: () -> Void

    @State private var detected = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            MarkerARContainer(onDetected: {
                guard !detected else { return }
                detected = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onDetected()
                }
            })
            .ignoresSafeArea()

            // Scanning overlay
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Viewfinder
                    ZStack {
                        ScannerCorners(color: detected ? .green : useCase.accentColor, size: 220)
                            .scaleEffect(pulse ? 1.04 : 1.0)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)

                        if detected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 52, weight: .semibold))
                                .foregroundColor(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3), value: detected)

                    VStack(spacing: 8) {
                        Text(detected ? "MARKER LOCKED" : "SCAN MARKER")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(detected ? .green : .white)

                        Text(detected ? "Establishing origin..." : "Point camera at the ArUco marker to begin")
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

            // Mode badge top
            VStack {
                HStack {
                    Label(useCase.title.uppercased(), systemImage: useCase.icon)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(useCase.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                Spacer()
            }
        }
        .onAppear { pulse = true }
    }
}


// MARK: - Corner tick shape

struct ScannerCorners: View {
    let color: Color
    let size: CGFloat
    let length: CGFloat = 28
    let lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            // Top-left
            Path { p in
                p.move(to: CGPoint(x: 0, y: length))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: length, y: 0))
            }
            .stroke(color, lineWidth: lineWidth)

            // Top-right
            Path { p in
                p.move(to: CGPoint(x: size - length, y: 0))
                p.addLine(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: length))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-left
            Path { p in
                p.move(to: CGPoint(x: 0, y: size - length))
                p.addLine(to: CGPoint(x: 0, y: size))
                p.addLine(to: CGPoint(x: length, y: size))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-right
            Path { p in
                p.move(to: CGPoint(x: size - length, y: size))
                p.addLine(to: CGPoint(x: size, y: size))
                p.addLine(to: CGPoint(x: size, y: size - length))
            }
            .stroke(color, lineWidth: lineWidth)
        }
        .frame(width: size, height: size)
    }
}


// MARK: - AR Container

struct MarkerARContainer: UIViewRepresentable {
    let onDetected: () -> Void

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        if let refs = ARReferenceImage.referenceImages(inGroupNamed: "Origin Reference Images", bundle: nil) {
            config.detectionImages = refs
            config.maximumNumberOfTrackedImages = 1
        }
        arView.session.run(config)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> MarkerCoordinator {
        MarkerCoordinator(onDetected: onDetected)
    }
}

class MarkerCoordinator: NSObject, ARSessionDelegate {
    weak var arView: ARView?
    let onDetected: () -> Void
    private var originSet = false

    init(onDetected: @escaping () -> Void) {
        self.onDetected = onDetected
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard !originSet else { return }
        for anchor in anchors.compactMap({ $0 as? ARImageAnchor }) {
            originSet = true

            let anchorMatrix = anchor.transform
            let position = anchorMatrix.columns.3

            var forward = simd_float3(anchorMatrix.columns.1.x, 0, anchorMatrix.columns.1.z)
            if simd_length(forward) < 0.001 {
                forward = simd_float3(anchorMatrix.columns.2.x, 0, anchorMatrix.columns.2.z)
            }
            forward = simd_normalize(forward)

            let up = simd_float3(0, 1, 0)
            let right = simd_normalize(simd_cross(up, forward))

            var gravityAligned = matrix_identity_float4x4
            gravityAligned.columns.0 = simd_float4(right, 0)
            gravityAligned.columns.1 = simd_float4(up, 0)
            gravityAligned.columns.2 = simd_float4(forward, 0)
            gravityAligned.columns.3 = position

            session.setWorldOrigin(relativeTransform: gravityAligned)

            DispatchQueue.main.async {
                self.onDetected()
            }
        }
    }
}

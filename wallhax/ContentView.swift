import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    var body: some View {
        ARViewContainer()
                    .ignoresSafeArea()
            }
        }

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.frameSemantics = .sceneDepth

        arView.session.delegate = context.coordinator
        arView.session.run(config)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
}

class Coordinator: NSObject, ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pos = frame.camera.transform.columns.3
        print("📍 pos: \(pos.x), \(pos.y), \(pos.z)")
    }
}Ï

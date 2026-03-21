import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    let useCase: UseCase
    var accentColor: Color { useCase.accentColor }
    
    @State private var showPinWheel = false
    @State private var selectedPinIndex: Int? = nil
    
    var body: some View {
        ZStack{
            ARViewContainer()
                .ignoresSafeArea()
            
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
        }
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
}

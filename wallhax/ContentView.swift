import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    let useCase: UseCase
    var accentColor: Color { useCase.accentColor }
    let onExit: () -> Void
    
    @State private var showPinWheel = false
    @State private var selectedPinIndex: Int? = nil
    @State private var isRecording = false
    
    var body: some View {
        ZStack{
            ARViewContainer(isRecording: $isRecording)
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

        let configuration = ARWorldTrackingConfiguration()
        if let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "Origin Reference Images", bundle: nil) {
            configuration.detectionImages = referenceImages
        }

        arView.session.run(configuration)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
    
}

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
    }

}

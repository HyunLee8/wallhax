import RealityKit
import UIKit
import simd

/// Renders 3D pin markers using RealityKit (same as peer avatars).
/// Completely self-contained — does not influence stick figures, minimap,
/// or any other orientation/coordinate logic.
enum PinRenderer {

    // MARK: - Pin Entity (stick + sphere + ring)

    static func makePinEntity(color: UIColor) -> Entity {
        let root = Entity()

        // Thin vertical stick
        let stickH: Float = 0.45
        let stickMesh = MeshResource.generateBox(width: 0.006, height: stickH, depth: 0.006)
        var stickMat = UnlitMaterial()
        stickMat.color = .init(tint: color.withAlphaComponent(0.6))
        let stick = ModelEntity(mesh: stickMesh, materials: [stickMat])
        stick.position.y = stickH / 2
        root.addChild(stick)

        // Pin head sphere
        let sphereMesh = MeshResource.generateSphere(radius: 0.035)
        var sphereMat = UnlitMaterial()
        sphereMat.color = .init(tint: color)
        let sphere = ModelEntity(mesh: sphereMesh, materials: [sphereMat])
        sphere.position.y = stickH + 0.035
        root.addChild(sphere)

        // Ground ring (flat torus approximated as a thin cylinder ring)
        let ringOuter = MeshResource.generateBox(width: 0.12, height: 0.005, depth: 0.12, cornerRadius: 0.06)
        var ringMat = UnlitMaterial()
        ringMat.color = .init(tint: color.withAlphaComponent(0.4))
        let ring = ModelEntity(mesh: ringOuter, materials: [ringMat])
        ring.position.y = 0.002
        ring.scale = SIMD3<Float>(1, 0.3, 1) // flatten
        root.addChild(ring)

        return root
    }

    // MARK: - Label Entity (text + background plate)

    static func makeLabelEntity(text: String, color: UIColor) -> Entity {
        let container = Entity()

        // Background plate
        let plateMesh = MeshResource.generatePlane(width: 0.22, depth: 0.10, cornerRadius: 0.015)
        var plateMat = UnlitMaterial()
        plateMat.color = .init(tint: color.withAlphaComponent(0.85))
        let plate = ModelEntity(mesh: plateMesh, materials: [plateMat])
        // Rotate plate from horizontal to vertical (face forward)
        plate.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        plate.position.z = -0.002
        container.addChild(plate)

        // Text
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.035, weight: .bold)
        )
        var textMat = UnlitMaterial()
        textMat.color = .init(tint: .white)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMat])
        textEntity.name = "pinLabelText"
        let bounds = textEntity.visualBounds(relativeTo: nil)
        textEntity.position.x = -bounds.center.x
        textEntity.position.y = -bounds.center.y
        container.addChild(textEntity)

        return container
    }

    // MARK: - Per-frame billboard + distance update

    /// Call each frame. Billboards labels toward camera and updates distance text.
    static func updatePins(
        pinAnchors: [UUID: AnchorEntity],
        pinLabels: [UUID: Entity],
        pins: [MapPin],
        cameraTransform: simd_float4x4
    ) {
        let camPos = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        for pin in pins {
            // Billboard label toward camera
            guard let label = pinLabels[pin.id] else { continue }
            let labelWorldPos = SIMD3<Float>(pin.position.x, pin.position.y + 0.55, pin.position.z)
            let toCamera = camPos - labelWorldPos
            let yaw = atan2(toCamera.x, toCamera.z)
            label.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

            // Update distance text
            let dist = simd_distance(camPos, pin.position)
            let distStr: String
            if dist < 1.0 {
                distStr = String(format: "%.1fm", dist)
            } else {
                distStr = String(format: "%.0fm", dist)
            }

            // Find text entity and rebuild if distance changed
            if let textEntity = label.findEntity(named: "pinLabelText") as? ModelEntity {
                let currentText = pin.label + " · " + distStr
                // Rebuild text mesh (RealityKit text meshes can't be mutated)
                let newMesh = MeshResource.generateText(
                    currentText,
                    extrusionDepth: 0.002,
                    font: .systemFont(ofSize: 0.035, weight: .bold)
                )
                textEntity.model?.mesh = newMesh
                let bounds = textEntity.visualBounds(relativeTo: nil)
                textEntity.position.x = -bounds.center.x
                textEntity.position.y = -bounds.center.y
            }
        }
    }
}

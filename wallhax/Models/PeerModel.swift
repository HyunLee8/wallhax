import SceneKit
import RealityKit
import UIKit

enum PeerModel {

    // MARK: - RealityKit entity (rendered directly in ARView — orientation is automatic)

    static func makeEntity(color: UIColor) -> Entity {
        let root = Entity()
        var mat = SimpleMaterial()
        mat.color = .init(tint: color)

        // Head
        let head = ModelEntity(mesh: .generateSphere(radius: 0.10), materials: [mat])
        head.position = [0, 0.80, 0]
        root.addChild(head)

        // Torso
        let torso = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.40, depth: 0.06, cornerRadius: 0.02), materials: [mat])
        torso.position = [0, 0.40, 0]
        root.addChild(torso)

        // Left arm
        let lArm = ModelEntity(mesh: .generateBox(width: 0.30, height: 0.044, depth: 0.044, cornerRadius: 0.015), materials: [mat])
        lArm.position = [-0.15, 0.55, 0]
        root.addChild(lArm)

        // Right arm
        let rArm = ModelEntity(mesh: .generateBox(width: 0.30, height: 0.044, depth: 0.044, cornerRadius: 0.015), materials: [mat])
        rArm.position = [0.15, 0.55, 0]
        root.addChild(rArm)

        // Left leg
        let lLeg = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.45, depth: 0.05, cornerRadius: 0.015), materials: [mat])
        lLeg.position = [-0.07, -0.28, 0]
        root.addChild(lLeg)

        // Right leg
        let rLeg = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.45, depth: 0.05, cornerRadius: 0.015), materials: [mat])
        rLeg.position = [0.07, -0.28, 0]
        root.addChild(rLeg)

        return root
    }

    // MARK: - SceneKit node (used by SCNView overlay for pins etc.)

    static func makeNode(color: UIColor) -> SCNNode {
        let root = SCNNode()
        let mat = material(color: color)

        // Head
        root.addChildNode(sphere(radius: 0.10, at: (0, 0.80, 0), mat: mat))
        // Torso
        root.addChildNode(cylinder(radius: 0.030, height: 0.40, at: (0, 0.40, 0), mat: mat))
        // Left arm
        root.addChildNode(cylinder(radius: 0.022, height: 0.30, at: (-0.15, 0.55, 0), eulerZ: .pi / 2, mat: mat))
        // Right arm
        root.addChildNode(cylinder(radius: 0.022, height: 0.30, at: (0.15, 0.55, 0), eulerZ: .pi / 2, mat: mat))
        // Left leg
        root.addChildNode(cylinder(radius: 0.025, height: 0.45, at: (-0.07, -0.28, 0), mat: mat))
        // Right leg
        root.addChildNode(cylinder(radius: 0.025, height: 0.45, at: (0.07, -0.28, 0), mat: mat))

        return root
    }

    private static func sphere(radius: Float, at pos: (Float, Float, Float), mat: SCNMaterial) -> SCNNode {
        let geo = SCNSphere(radius: CGFloat(radius))
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(pos.0, pos.1, pos.2)
        return node
    }

    private static func cylinder(radius: Float, height: Float, at pos: (Float, Float, Float), eulerZ: Float = 0, mat: SCNMaterial) -> SCNNode {
        let geo = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(pos.0, pos.1, pos.2)
        if eulerZ != 0 {
            node.eulerAngles.z = eulerZ
        }
        return node
    }

    private static func material(color: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color.withAlphaComponent(0.5)
        mat.readsFromDepthBuffer = false
        mat.writesToDepthBuffer = false
        mat.isDoubleSided = true
        return mat
    }
}

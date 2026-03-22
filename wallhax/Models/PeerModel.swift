import SceneKit
import UIKit

enum PeerModel {
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

import SceneKit
import RealityKit
import UIKit

enum PeerModel {

    // MARK: - RealityKit entity (rendered directly in ARView — orientation is automatic)

    static func makeEntity(color: UIColor) -> Entity {
        let root = Entity()
        var mat = SimpleMaterial()
        mat.color = .init(tint: color)

        // Head — block shape, rotates with phone pitch
        let head = ModelEntity(mesh: .generateBox(width: 0.12, height: 0.14, depth: 0.12, cornerRadius: 0.02), materials: [mat])
        head.name = "head"
        head.position = [0, 0.80, 0]
        root.addChild(head)

        // Torso
        let torso = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.40, depth: 0.06, cornerRadius: 0.02), materials: [mat])
        torso.name = "torso"
        torso.position = [0, 0.40, 0]
        root.addChild(torso)

        // Left arm
        let lArm = ModelEntity(mesh: .generateBox(width: 0.30, height: 0.044, depth: 0.044, cornerRadius: 0.015), materials: [mat])
        lArm.name = "lArm"
        lArm.position = [-0.15, 0.55, 0]
        root.addChild(lArm)

        // Right arm
        let rArm = ModelEntity(mesh: .generateBox(width: 0.30, height: 0.044, depth: 0.044, cornerRadius: 0.015), materials: [mat])
        rArm.name = "rArm"
        rArm.position = [0.15, 0.55, 0]
        root.addChild(rArm)

        // Left leg
        let lLeg = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.45, depth: 0.05, cornerRadius: 0.015), materials: [mat])
        lLeg.name = "lLeg"
        lLeg.position = [-0.07, -0.28, 0]
        root.addChild(lLeg)

        // Right leg
        let rLeg = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.45, depth: 0.05, cornerRadius: 0.015), materials: [mat])
        rLeg.name = "rLeg"
        rLeg.position = [0.07, -0.28, 0]
        root.addChild(rLeg)

        return root
    }

    /// Pose the figure based on camera pitch and height above floor.
    /// - pitch: camera pitch in radians (negative = looking down, positive = looking up)
    /// - heightAboveFloor: estimated height of the phone above the floor in meters
    static func applyPose(to figure: Entity, pitch: Float, heightAboveFloor: Float) {
        guard let head = figure.children.first(where: { $0.name == "head" }),
              let torso = figure.children.first(where: { $0.name == "torso" }),
              let lArm = figure.children.first(where: { $0.name == "lArm" }),
              let rArm = figure.children.first(where: { $0.name == "rArm" }),
              let lLeg = figure.children.first(where: { $0.name == "lLeg" }),
              let rLeg = figure.children.first(where: { $0.name == "rLeg" })
        else { return }

        // Clamp head pitch to ±45 degrees
        let clampedPitch = max(-.pi / 4, min(.pi / 4, pitch))
        // Head pitch: rotate around local X axis (left-right axis)
        head.orientation = simd_quatf(angle: clampedPitch, axis: [1, 0, 0])

        let h = heightAboveFloor

        if h < 0.9 {
            // PRONE — lying flat on the ground (below ~3 feet)
            // Rotate entire figure to lay horizontal, face down
            figure.position.y = -0.80 + 0.05  // just above ground
            // Tilt the whole body forward 90 degrees
            let torsoAngle: Float = -.pi / 2
            torso.orientation = simd_quatf(angle: torsoAngle, axis: [1, 0, 0])
            torso.position = [0, 0.10, 0.20]

            head.position = [0, 0.10, 0.45]
            head.orientation = simd_quatf(angle: torsoAngle + clampedPitch, axis: [1, 0, 0])

            lArm.position = [-0.15, 0.10, 0.30]
            lArm.orientation = simd_quatf(angle: torsoAngle, axis: [1, 0, 0])
            rArm.position = [0.15, 0.10, 0.30]
            rArm.orientation = simd_quatf(angle: torsoAngle, axis: [1, 0, 0])

            lLeg.position = [-0.07, 0.10, -0.20]
            lLeg.orientation = simd_quatf(angle: torsoAngle, axis: [1, 0, 0])
            rLeg.position = [0.07, 0.10, -0.20]
            rLeg.orientation = simd_quatf(angle: torsoAngle, axis: [1, 0, 0])

        } else if h < 1.5 {
            // CROUCHING — between ~3 and ~5 feet
            let crouchFactor = 1.0 - ((h - 0.9) / 0.6) // 1.0 at 0.9m, 0.0 at 1.5m
            let legBend: Float = crouchFactor * 0.6  // radians, how much legs bend
            let drop: Float = crouchFactor * 0.30    // how much the body drops

            figure.position.y = -0.80

            torso.position = SIMD3(0, 0.40 - drop, 0)
            torso.orientation = simd_quatf(angle: crouchFactor * 0.3, axis: [1, 0, 0]) // slight forward lean

            head.position = SIMD3(0, 0.80 - drop, 0)

            lArm.position = SIMD3(-0.15, 0.55 - drop, 0)
            lArm.orientation = .init()
            rArm.position = SIMD3(0.15, 0.55 - drop, 0)
            rArm.orientation = .init()

            // Legs bend at knees
            lLeg.position = SIMD3(-0.07, -0.28 + drop * 0.3, -0.05 * crouchFactor)
            lLeg.orientation = simd_quatf(angle: legBend, axis: [1, 0, 0])
            rLeg.position = SIMD3(0.07, -0.28 + drop * 0.3, -0.05 * crouchFactor)
            rLeg.orientation = simd_quatf(angle: legBend, axis: [1, 0, 0])

        } else {
            // STANDING — normal upright pose (above ~5 feet)
            figure.position.y = -0.80

            torso.position = [0, 0.40, 0]
            torso.orientation = .init()

            head.position = [0, 0.80, 0]
            // head.orientation already set above for pitch

            lArm.position = [-0.15, 0.55, 0]
            lArm.orientation = .init()
            rArm.position = [0.15, 0.55, 0]
            rArm.orientation = .init()

            lLeg.position = [-0.07, -0.28, 0]
            lLeg.orientation = .init()
            rLeg.position = [0.07, -0.28, 0]
            rLeg.orientation = .init()
        }
    }

    // MARK: - Dashed wireframe outline (shown when peer is behind a wall/floor)

    static func makeOutlineEntity(color: UIColor) -> Entity {
        let root = Entity()
        var verts: [SIMD3<Float>] = []
        var norms: [SIMD3<Float>] = []
        var tris: [UInt32] = []

        let t: Float = 0.003       // half-thickness of edge lines
        let dashLen: Float = 0.025
        let gapLen: Float = 0.018

        // Add a thin box (8 verts, 12 tris)
        func addBox(center c: SIMD3<Float>, halfExtent h: SIMD3<Float>) {
            let base = UInt32(verts.count)
            let corners: [SIMD3<Float>] = [
                c + SIMD3(-h.x, -h.y, -h.z), c + SIMD3(+h.x, -h.y, -h.z),
                c + SIMD3(+h.x, +h.y, -h.z), c + SIMD3(-h.x, +h.y, -h.z),
                c + SIMD3(-h.x, -h.y, +h.z), c + SIMD3(+h.x, -h.y, +h.z),
                c + SIMD3(+h.x, +h.y, +h.z), c + SIMD3(-h.x, +h.y, +h.z),
            ]
            verts.append(contentsOf: corners)
            for _ in 0..<8 { norms.append(SIMD3(0, 1, 0)) }
            let faces: [(UInt32, UInt32, UInt32, UInt32)] = [
                (0,1,2,3), (5,4,7,6), (4,0,3,7), (1,5,6,2), (3,2,6,7), (4,5,1,0),
            ]
            for (a,b,c,d) in faces {
                tris.append(contentsOf: [base+a, base+b, base+c])
                tris.append(contentsOf: [base+a, base+c, base+d])
            }
        }

        // Dashed edge along one axis
        func dashedEdge(from: Float, to: Float, axis: Int, pos: SIMD3<Float>) {
            var cursor = min(from, to)
            let end = max(from, to)
            while cursor < end {
                let dashEnd = min(cursor + dashLen, end)
                let mid = (cursor + dashEnd) / 2
                let halfLen = (dashEnd - cursor) / 2
                var center = pos
                var halfExtent = SIMD3<Float>(t, t, t)
                center[axis] = mid
                halfExtent[axis] = halfLen
                addBox(center: center, halfExtent: halfExtent)
                cursor += dashLen + gapLen
            }
        }

        // Dashed segment between two arbitrary points
        func dashedSegment(from p1: SIMD3<Float>, to p2: SIMD3<Float>) {
            let dir = p2 - p1
            let totalLen = simd_length(dir)
            guard totalLen > 0.001 else { return }
            let fwd = dir / totalLen
            let up: SIMD3<Float> = abs(fwd.y) < 0.9 ? SIMD3(0,1,0) : SIMD3(1,0,0)
            let right = simd_normalize(simd_cross(fwd, up))
            let realUp = simd_normalize(simd_cross(right, fwd))

            var cursor: Float = 0
            while cursor < totalLen {
                let dashEnd = min(cursor + dashLen, totalLen)
                let mid = (cursor + dashEnd) / 2
                let halfLen = (dashEnd - cursor) / 2
                let center = p1 + fwd * mid

                let base = UInt32(verts.count)
                for (sx, sy, sz) in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                                     (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)] as [(Float,Float,Float)] {
                    let p = center + right * (sx * t) + realUp * (sy * t) + fwd * (sz * halfLen)
                    verts.append(p)
                    norms.append(realUp)
                }
                let faces: [(UInt32,UInt32,UInt32,UInt32)] = [
                    (0,1,2,3),(5,4,7,6),(4,0,3,7),(1,5,6,2),(3,2,6,7),(4,5,1,0),
                ]
                for (a,b,c,d) in faces {
                    tris.append(contentsOf: [base+a, base+b, base+c])
                    tris.append(contentsOf: [base+a, base+c, base+d])
                }
                cursor += dashLen + gapLen
            }
        }

        // Box body parts: center, size
        let parts: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(0, 0.40, 0),    SIMD3(0.06, 0.40, 0.06)),   // Torso
            (SIMD3(-0.15, 0.55, 0), SIMD3(0.30, 0.044, 0.044)), // Left arm
            (SIMD3(0.15, 0.55, 0),  SIMD3(0.30, 0.044, 0.044)), // Right arm
            (SIMD3(-0.07, -0.28, 0), SIMD3(0.05, 0.45, 0.05)),  // Left leg
            (SIMD3(0.07, -0.28, 0),  SIMD3(0.05, 0.45, 0.05)),  // Right leg
        ]

        for (center, size) in parts {
            let hs = size / 2
            // 4 edges along X
            for (ey, ez) in [(-hs.y, -hs.z), (hs.y, -hs.z), (hs.y, hs.z), (-hs.y, hs.z)] {
                dashedEdge(from: center.x - hs.x, to: center.x + hs.x, axis: 0,
                           pos: SIMD3(0, center.y + ey, center.z + ez))
            }
            // 4 edges along Y
            for (ex, ez) in [(-hs.x, -hs.z), (hs.x, -hs.z), (hs.x, hs.z), (-hs.x, hs.z)] {
                dashedEdge(from: center.y - hs.y, to: center.y + hs.y, axis: 1,
                           pos: SIMD3(center.x + ex, 0, center.z + ez))
            }
            // 4 edges along Z
            for (ex, ey) in [(-hs.x, -hs.y), (hs.x, -hs.y), (hs.x, hs.y), (-hs.x, hs.y)] {
                dashedEdge(from: center.z - hs.z, to: center.z + hs.z, axis: 2,
                           pos: SIMD3(center.x + ex, center.y + ey, 0))
            }
        }

        // Head: block outline (0.12 x 0.14 x 0.12 at y=0.80)
        let headPart: (SIMD3<Float>, SIMD3<Float>) = (SIMD3(0, 0.80, 0), SIMD3(0.12, 0.14, 0.12))
        do {
            let (center, size) = headPart
            let hs = size / 2
            for (ey, ez) in [(-hs.y, -hs.z), (hs.y, -hs.z), (hs.y, hs.z), (-hs.y, hs.z)] {
                dashedEdge(from: center.x - hs.x, to: center.x + hs.x, axis: 0,
                           pos: SIMD3(0, center.y + ey, center.z + ez))
            }
            for (ex, ez) in [(-hs.x, -hs.z), (hs.x, -hs.z), (hs.x, hs.z), (-hs.x, hs.z)] {
                dashedEdge(from: center.y - hs.y, to: center.y + hs.y, axis: 1,
                           pos: SIMD3(center.x + ex, 0, center.z + ez))
            }
            for (ex, ey) in [(-hs.x, -hs.y), (hs.x, -hs.y), (hs.x, hs.y), (-hs.x, hs.y)] {
                dashedEdge(from: center.z - hs.z, to: center.z + hs.z, axis: 2,
                           pos: SIMD3(center.x + ex, center.y + ey, 0))
            }
        }

        guard !verts.isEmpty else { return root }

        var descriptor = MeshDescriptor(name: "peerOutline")
        descriptor.positions = MeshBuffer(verts)
        descriptor.normals = MeshBuffer(norms)
        descriptor.primitives = .triangles(tris)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return root }
        var mat = UnlitMaterial()
        mat.color = .init(tint: color)
        let entity = ModelEntity(mesh: mesh, materials: [mat])
        root.addChild(entity)
        return root
    }

    static func makeNameplate(text: String) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.005,
            font: .systemFont(ofSize: 0.08, weight: .bold)
        )
        var mat = UnlitMaterial()
        mat.color = .init(tint: .black)
        let entity = ModelEntity(mesh: mesh, materials: [mat])
        // Center the text horizontally based on its actual bounds
        let bounds = entity.visualBounds(relativeTo: nil)
        entity.position.x = -bounds.center.x
        entity.position.y = -bounds.center.y
        return entity
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

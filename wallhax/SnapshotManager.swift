//
//  SnapshotManager.swift
//  wallhax-ios
//
//  Captures full-res camera frames + XMP sidecar files with pose data.
//  Each frame produces: frame_00001.jpg + frame_00001.xmp
//  Flat structure inside scan_<timestamp>/
//

import Foundation
import ARKit
import UIKit

class SnapshotManager {
    
    static let shared = SnapshotManager()
    
    // ── Config ─────────────────────────────────────────────────
    private let captureInterval: TimeInterval = 0.1
    private let jpegQuality: CGFloat = 0.95
    private let minMovement: Float = 0.05   // 5cm
    private let minRotation: Float = 0.087  // ~5 degrees
    
    // ── State ──────────────────────────────────────────────────
    private var isCapturing = false
    private var frameIndex = 0
    private var lastCaptureTime: TimeInterval = 0
    private var lastCapturePosition: SIMD3<Float>?
    private var lastCaptureRotation: simd_float3x3?

    private var accumulatedPoints: [SIMD3<Float>] = []
    
    private var sessionDir: URL?
    
    private var intrinsics: simd_float3x3?
    private var imageWidth: Int = 0
    private var imageHeight: Int = 0
    
    private init() {}
    
    // ── Public API ─────────────────────────────────────────────
    
    func startSession() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let sessionName = "scan_\(formatter.string(from: Date()))"
        
        sessionDir = docs.appendingPathComponent(sessionName)
        try? FileManager.default.createDirectory(at: sessionDir!, withIntermediateDirectories: true)
        
        frameIndex = 0
        lastCaptureTime = 0
        lastCapturePosition = nil
        lastCaptureRotation = nil
        intrinsics = nil
        isCapturing = true
        
        print("[SnapshotManager] Session started: \(sessionName)")
        print("[SnapshotManager] Saving to: \(sessionDir!.path)")
    }
    
    func stopSession() {
        guard isCapturing else { return }
        isCapturing = false

        if let sessionDir = sessionDir, !accumulatedPoints.isEmpty {
            let pointsArray = accumulatedPoints.map { [$0.x, $0.y, $0.z] }
            if let data = try? JSONSerialization.data(withJSONObject: pointsArray) {
                let url = sessionDir.appendingPathComponent("points.json")
                try? data.write(to: url)
                print("[SnapshotManager] Saved \(accumulatedPoints.count) 3D points to points.json")
            }
        }

        print("[SnapshotManager] Session stopped. \(frameIndex) frames captured.")
    }
    
    func processFrame(_ frame: ARFrame) {
        guard isCapturing else { return }
        guard frame.camera.trackingState == .normal else { return }
        
        let now = frame.timestamp
        guard (now - lastCaptureTime) >= captureInterval else { return }
        
        let t = frame.camera.transform
        let currentPos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let currentRot = simd_float3x3(
            SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z),
            SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z),
            SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        )
        
        if let lastPos = lastCapturePosition, let lastRot = lastCaptureRotation {
            let dist = simd_distance(currentPos, lastPos)
            let relRot = currentRot * lastRot.transpose
            let trace = relRot.columns.0.x + relRot.columns.1.y + relRot.columns.2.z
            let angle = acos(max(-1.0, min(1.0, (trace - 1.0) / 2.0)))
            if dist < minMovement && angle < minRotation {
                return
            }
        }
        
        // ── Capture ────────────────────────────────────────────
        
        if intrinsics == nil {
            intrinsics = frame.camera.intrinsics
            let imgRes = frame.camera.imageResolution
            // Swapped: ARKit reports landscape dimensions, we save portrait
            imageWidth = Int(imgRes.height)
            imageHeight = Int(imgRes.width)
        }

        if let rawFeatures = frame.rawFeaturePoints {
            for point in rawFeatures.points {
                accumulatedPoints.append(point)
            }
        }
        
        // Convert pixel buffer to JPEG (ARKit delivers landscape-left, rotate to portrait)
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        // Re-render with orientation baked in
        UIGraphicsBeginImageContext(uiImage.size)
        uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let finalImage = rotatedImage,
              let jpegData = finalImage.jpegData(compressionQuality: jpegQuality) else { return }
        
        let baseName = String(format: "frame_%05d", frameIndex)
        let jpgURL = sessionDir!.appendingPathComponent("\(baseName).jpg")
        let xmpURL = sessionDir!.appendingPathComponent("\(baseName).xmp")
        
        // Save JPEG
        do {
            try jpegData.write(to: jpgURL)
        } catch {
            print("[SnapshotManager] Failed to write image: \(error)")
            return
        }
        
        // ── Build XMP sidecar ──────────────────────────────────
        let m = frame.camera.transform
        let K = intrinsics!
        
        let fl_x = K.columns.0.x
        let fl_y = K.columns.1.y
        let cx = K.columns.2.x
        let cy = K.columns.2.y
        
        // Quaternion from rotation matrix
        let quat = simd_quatf(frame.camera.transform)
        
        let xmpString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:wallhax="http://wallhax.io/ns/1.0/"
              xmlns:camera="http://wallhax.io/ns/camera/1.0/"
              xmlns:pose="http://wallhax.io/ns/pose/1.0/"
              xmlns:tiff="http://ns.adobe.com/tiff/1.0/">

              <!-- Image Info -->
              <tiff:ImageWidth>\(imageWidth)</tiff:ImageWidth>
              <tiff:ImageLength>\(imageHeight)</tiff:ImageLength>

              <!-- Camera Intrinsics -->
              <camera:FocalLengthX>\(fl_x)</camera:FocalLengthX>
              <camera:FocalLengthY>\(fl_y)</camera:FocalLengthY>
              <camera:PrincipalPointX>\(cx)</camera:PrincipalPointX>
              <camera:PrincipalPointY>\(cy)</camera:PrincipalPointY>
              <camera:Model>OPENCV</camera:Model>
              <camera:K1>0.0</camera:K1>
              <camera:K2>0.0</camera:K2>
              <camera:P1>0.0</camera:P1>
              <camera:P2>0.0</camera:P2>

              <!-- Camera Pose (camera-to-world) -->
              <!-- Position (meters) -->
              <pose:PositionX>\(m.columns.3.x)</pose:PositionX>
              <pose:PositionY>\(m.columns.3.y)</pose:PositionY>
              <pose:PositionZ>\(m.columns.3.z)</pose:PositionZ>

              <!-- Quaternion (w, x, y, z) -->
              <pose:QuaternionW>\(quat.real)</pose:QuaternionW>
              <pose:QuaternionX>\(quat.imag.x)</pose:QuaternionX>
              <pose:QuaternionY>\(quat.imag.y)</pose:QuaternionY>
              <pose:QuaternionZ>\(quat.imag.z)</pose:QuaternionZ>

              <!-- Full 4x4 Transform Matrix (row-major) -->
              <pose:TransformMatrix>\(m.columns.0.x) \(m.columns.1.x) \(m.columns.2.x) \(m.columns.3.x) \(m.columns.0.y) \(m.columns.1.y) \(m.columns.2.y) \(m.columns.3.y) \(m.columns.0.z) \(m.columns.1.z) \(m.columns.2.z) \(m.columns.3.z) \(m.columns.0.w) \(m.columns.1.w) \(m.columns.2.w) \(m.columns.3.w)</pose:TransformMatrix>

              <!-- Metadata -->
              <wallhax:Timestamp>\(frame.timestamp)</wallhax:Timestamp>
              <wallhax:FrameIndex>\(frameIndex)</wallhax:FrameIndex>
              <wallhax:TrackingState>\(trackingStateString(frame.camera.trackingState))</wallhax:TrackingState>

            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        
        // Save XMP
        do {
            try xmpString.write(to: xmpURL, atomically: true, encoding: .utf8)
        } catch {
            print("[SnapshotManager] Failed to write XMP: \(error)")
        }
        
        lastCaptureTime = now
        lastCapturePosition = currentPos
        lastCaptureRotation = currentRot
        frameIndex += 1
        
        if frameIndex % 10 == 0 {
            print("[SnapshotManager] Captured \(frameIndex) frames")
        }
    }
    
    func forceCapture(_ frame: ARFrame) {
        lastCaptureTime = 0
        lastCapturePosition = nil
        lastCaptureRotation = nil
        processFrame(frame)
    }
    
    // ── Helpers ────────────────────────────────────────────────
    
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
    
    var sessionPath: String? {
        return sessionDir?.path
    }
    
    var capturedFrameCount: Int {
        return frameIndex
    }
}

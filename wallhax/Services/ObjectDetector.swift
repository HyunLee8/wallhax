import Vision
import ARKit
import UIKit

struct DetectedObject: Identifiable {
    let id = UUID()
    let type: String              // "DOOR"
    let normalizedBounds: CGRect  // Vision coords (bottom-left origin, 0-1)
    let confidence: Float
}

/// Detects door-shaped rectangles using Vision framework.
/// Publishes results to ARState.detectedObjects for overlay rendering.
class ObjectDetector {
    static let shared = ObjectDetector()

    private var lastTime: TimeInterval = 0
    private let interval: TimeInterval = 0.3

    private init() {}

    func processFrame(_ frame: ARFrame) {
        let now = frame.timestamp
        guard now - lastTime >= interval else { return }
        lastTime = now

        let buf = frame.capturedImage

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.15
        request.maximumAspectRatio = 0.65
        request.minimumSize = 0.08
        request.maximumObservations = 5
        request.minimumConfidence = 0.65

        let handler = VNImageRequestHandler(cvPixelBuffer: buf, orientation: .right)

        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])

            var results: [DetectedObject] = []

            if let rects = request.results {
                for r in rects {
                    let bb = r.boundingBox
                    let ar = bb.height / bb.width
                    guard ar >= 1.3 && ar <= 3.5 && bb.height >= 0.2 else { continue }
                    results.append(DetectedObject(
                        type: "DOOR",
                        normalizedBounds: bb,
                        confidence: r.confidence
                    ))
                }
            }

            DispatchQueue.main.async {
                ARState.shared.detectedObjects = results
            }
        }
    }

    func reset() {
        DispatchQueue.main.async {
            ARState.shared.detectedObjects = []
        }
    }
}

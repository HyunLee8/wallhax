import SwiftUI
import ARKit
import Combine

// MARK: - Military Operations View

struct MilitaryOperationsView: View {
    let useCase: UseCase
    let callsign: String
    let onExit: () -> Void

    @StateObject private var arState = ARState.shared
    @AppStorage("lidarEnabled") private var lidarEnabled = true
    @State private var lidarLoading = false
    @State private var isRecording = false
    @State private var hasRecording = false
    @State private var frameCount = 0
    @State private var isSending = false
    @State private var sendStatus = ""
    @State private var showPinWheel = false
    @State private var selectedPinIndex: Int? = nil
    @State private var showFullMap = false
    @State private var recordingStartTime: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var zuluTime: String = ""
    @State private var blinkOn = true

    let timer      = Timer.publish(every: 1,   on: .main, in: .common).autoconnect()
    let blinkTimer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    // ── Colors ──────────────────────────────────────────────────
    private let gray     = Color(red: 0.60, green: 0.62, blue: 0.66)
    private let grayDim  = Color(red: 0.60, green: 0.62, blue: 0.66).opacity(0.35)
    private let red      = Color(red: 0.95, green: 0.20, blue: 0.18)
    private let redDim   = Color(red: 0.95, green: 0.20, blue: 0.18).opacity(0.30)

    var body: some View {
        ZStack {
            // AR camera feed
            ARViewContainer(isRecording: $isRecording, lidarEnabled: $lidarEnabled)
                .edgesIgnoringSafeArea(.all)
                .allowsHitTesting(false)

            if arState.originLocked {
            // Recording edge glow
            if isRecording {
                RecordingVignette(red: red, blinkOn: blinkOn)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            // Detection overlays — the main feature
            DetectionOverlayView(objects: arState.detectedObjects, red: red, gray: gray)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            // Minimal crosshair
            MinimalCrosshair(gray: gray, red: red)
                .allowsHitTesting(false)

            // HUD
            VStack(spacing: 0) {
                topStrip
                    .padding(.top, 54)

                HStack(alignment: .top) {
                    // Minimap — floating in top-left under the strip
                    MinimapView(
                        trajectory: arState.trajectory,
                        currentPos: SIMD2<Float>(arState.position.x, arState.position.z),
                        heading: arState.heading,
                        pins: arState.pins,
                        peers: arState.peers,
                        walls: arState.walls,
                        accentColor: gray,
                        onTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showFullMap = true
                            }
                        }
                    )
                    .padding(.leading, 14)
                    .padding(.top, 8)

                    Spacer()
                }

                Spacer()

                if !sendStatus.isEmpty { sendBadge }

                perfLine
                    .padding(.bottom, 4)

                CompassBar(heading: arState.heading, gray: gray, red: red)
                    .padding(.bottom, 8)

                controls
                    .padding(.bottom, 44)
            }

            // Pin wheel
            if showPinWheel {
                PinWheelOverlay(
                    labels: useCase.pinLabels,
                    accentColor: red,
                    selectedIndex: selectedPinIndex,
                    useCaseId: useCase.id
                )
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .zIndex(15)
            }
            } // end if originLocked

            // Full map
            if showFullMap {
                FullMap3DView(
                    trajectory: arState.trajectory,
                    currentPos: arState.position,
                    heading: arState.heading,
                    pins: arState.pins,
                    peers: arState.peers,
                    walls: arState.walls,
                    floors: arState.floors,
                    accentColor: gray,
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFullMap = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            // ── Marker scan overlay ───────────────────────────────
            if !arState.originLocked {
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 24) {
                        ScannerCorners(color: gray, size: 220)
                        VStack(spacing: 8) {
                            Text("SCAN MARKER")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.white)
                            Text("Point camera at the ArUco marker to begin")
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
                .transition(.opacity)
                .zIndex(20)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            updateZuluTime()
            if isRecording {
                frameCount = SnapshotManager.shared.capturedFrameCount
                if let start = recordingStartTime { elapsed = Date().timeIntervalSince(start) }
            }
        }
        .onReceive(blinkTimer) { _ in blinkOn.toggle() }
    }

    // MARK: - Top Strip

    private var topStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // EXFIL
                Button(action: { ARState.shared.reset(); onExit() }) {
                    Text("\u{2039} EXFIL")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(red)
                }

                Spacer()

                // Status pips
                HStack(spacing: 14) {
                    pip(trackingColor, "TRK")
                    pip(arState.isRelayConnected ? gray : red,
                        arState.isRelayConnected ? "UDP" : "UDP\u{2009}\u{2717}")
                    pip(arState.isTCPConnected ? gray : red,
                        arState.isTCPConnected ? "TCP" : "TCP\u{2009}\u{2717}")
                    if isRecording {
                        pip(blinkOn ? red : red.opacity(0.15), "REC \(fmtTime(elapsed))")
                    }
                }

                Spacer()

                // Callsign + DTG
                HStack(spacing: 10) {
                    Text(callsign.uppercased())
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(gray)
                    Text(zuluTime)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(gray.opacity(0.6))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            // Thin red line
            Rectangle().fill(red.opacity(0.35)).frame(height: 1)
        }
    }

    // MARK: - Performance Line (tiny)

    private var perfLine: some View {
        HStack(spacing: 16) {
            perfStat("FEAT", "\(arState.featureCount)")
            perfStat("DIST", String(format: "%.1fm", arState.distanceWalked))
            perfStat("PINS", "\(arState.pins.count)")
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func perfStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(grayDim)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(gray.opacity(0.6))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            // Mark button
            pillButton(
                icon: "mappin",
                label: "MARK",
                fg: showPinWheel ? .white : gray,
                border: showPinWheel ? red : gray.opacity(0.25)
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        switch value {
                        case .first: break
                        case .second(let lp, let drag):
                            if lp && !showPinWheel {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showPinWheel = true }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            if let drag = drag { updatePinSelection(dragLoc: drag.location) }
                        }
                    }
                    .onEnded { _ in
                        if showPinWheel, let idx = selectedPinIndex {
                            let label = useCase.pinLabels[idx].label
                            ARState.shared.requestDropPin?(label, UIColor(gray))
                            NetworkingManager.shared.sendPin(position: arState.position, label: label)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        withAnimation(.spring(response: 0.25)) { showPinWheel = false }
                        selectedPinIndex = nil
                    }
            )

            // Record — big center button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(isRecording ? red : Color.black.opacity(0.5))
                        .frame(width: 62, height: 62)
                        .overlay(Circle().stroke(isRecording ? red.opacity(0.6) : gray.opacity(0.25), lineWidth: 2))
                        .shadow(color: isRecording ? red.opacity(0.4) : .clear, radius: 12)

                    if isRecording {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white)
                            .frame(width: 18, height: 18)
                    } else {
                        Circle()
                            .fill(red)
                            .frame(width: 24, height: 24)
                    }
                }
            }

            // LiDAR toggle
            Button(action: {
                lidarLoading = true
                lidarEnabled.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { lidarLoading = false }
            }) {
                pillButton(
                    icon: "lidar.scanner",
                    label: lidarEnabled ? "ON" : "OFF",
                    fg: lidarEnabled ? gray : grayDim,
                    border: lidarEnabled ? gray.opacity(0.3) : gray.opacity(0.12)
                )
            }
            .disabled(lidarLoading)

            // TX button
            if hasRecording && !isRecording {
                Button(action: sendToMac) {
                    pillButton(
                        icon: "arrow.up",
                        label: "TX",
                        fg: red,
                        border: red.opacity(0.4)
                    )
                }
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 16)
    }

    private func pillButton(icon: String, label: String, fg: Color, border: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundColor(fg)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(border, lineWidth: 1))
    }

    // MARK: - Send Badge

    private var sendBadge: some View {
        Text(sendStatus)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
            .padding(.bottom, 6)
    }

    // MARK: - Helpers

    private func pip(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private var trackingColor: Color {
        switch arState.trackingState {
        case "normal":                       return gray
        case "initializing", "relocalizing": return .yellow
        default:                             return red
        }
    }

    private func fmtTime(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func updateZuluTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        zuluTime = String(format: "%02d%02d%02dZ",
                          cal.component(.hour,   from: now),
                          cal.component(.minute, from: now),
                          cal.component(.second, from: now))
    }

    private var wheelCenter: CGPoint {
        let s = UIScreen.main.bounds
        return CGPoint(x: s.width / 2, y: s.height * 0.42)
    }

    private func updatePinSelection(dragLoc: CGPoint) {
        let wc = wheelCenter
        let dx = dragLoc.x - wc.x
        let dy = dragLoc.y - wc.y
        guard sqrt(dx * dx + dy * dy) > 44 else { selectedPinIndex = nil; return }
        let count = useCase.pinLabels.count
        let step  = 2 * Double.pi / Double(count)
        let angle = Double(atan2(dy, dx))
        var best = 0; var bestDiff = Double.infinity
        for i in 0..<count {
            let a = -Double.pi / 2 + Double(i) * step
            var d = abs(angle - a)
            if d > .pi { d = 2 * .pi - d }
            if d < bestDiff { bestDiff = d; best = i }
        }
        let newIndex = bestDiff < step / 2 + 0.05 ? best : nil
        if newIndex != selectedPinIndex {
            if newIndex != nil { UISelectionFeedbackGenerator().selectionChanged() }
            selectedPinIndex = newIndex
        }
    }

    private func toggleRecording() {
        if isRecording {
            isRecording = false
            SnapshotManager.shared.stopSession()
            hasRecording = true
            recordingStartTime = nil
        } else {
            SnapshotManager.shared.startSession()
            isRecording = true
            hasRecording = false
            frameCount = 0
            sendStatus = ""
            recordingStartTime = Date()
            elapsed = 0
        }
    }

    private func sendToMac() {
        guard let sessionPath = SnapshotManager.shared.sessionPath else {
            sendStatus = "NO DATA"; return
        }
        isSending = true
        NetworkingManager.shared.sendToMac(sessionPath: sessionPath) { done, success, status in
            sendStatus = status
            if done { isSending = false; if success { hasRecording = false } }
        }
    }
}


// MARK: - Detection Overlay View

struct DetectionOverlayView: View {
    let objects: [DetectedObject]
    let red: Color
    let gray: Color

    var body: some View {
        GeometryReader { geo in
            ForEach(objects) { obj in
                let rect = screenRect(obj.normalizedBounds, in: geo.size)

                // Dashed outline
                Rectangle()
                    .strokeBorder(
                        red,
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Corner ticks for emphasis
                DetectionCorners(
                    rect: rect,
                    color: red,
                    armLength: min(rect.width, rect.height) * 0.2
                )

                // Label
                HStack(spacing: 4) {
                    Image(systemName: "door.left.hand.open")
                        .font(.system(size: 8, weight: .bold))
                    Text("DOOR")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(2)
                    Text(String(format: "%.0f%%", obj.confidence * 100))
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundColor(gray.opacity(0.6))
                }
                .foregroundColor(red)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.6))
                .cornerRadius(3)
                .position(x: rect.midX, y: rect.minY - 12)
            }
        }
    }

    private func screenRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: (1 - normalized.origin.y - normalized.height) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}

// MARK: - Detection Corner Ticks

struct DetectionCorners: View {
    let rect: CGRect
    let color: Color
    let armLength: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let lw: CGFloat = 2
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: rect.minX, y: rect.minY),  1,  1),
                (CGPoint(x: rect.maxX, y: rect.minY), -1,  1),
                (CGPoint(x: rect.minX, y: rect.maxY),  1, -1),
                (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
            ]
            for (origin, dx, dy) in corners {
                var p = Path()
                p.move(to: CGPoint(x: origin.x + armLength * dx, y: origin.y))
                p.addLine(to: origin)
                p.addLine(to: CGPoint(x: origin.x, y: origin.y + armLength * dy))
                ctx.stroke(p, with: .color(color), lineWidth: lw)
            }
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Minimal Crosshair

struct MinimalCrosshair: View {
    let gray: Color
    let red: Color

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let gap: CGFloat = 12
            let len: CGFloat = 16

            ZStack {
                // Four thin lines
                Rectangle().fill(gray.opacity(0.5)).frame(width: 1, height: len)
                    .position(x: cx, y: cy - gap - len / 2)
                Rectangle().fill(gray.opacity(0.5)).frame(width: 1, height: len)
                    .position(x: cx, y: cy + gap + len / 2)
                Rectangle().fill(gray.opacity(0.5)).frame(width: len, height: 1)
                    .position(x: cx - gap - len / 2, y: cy)
                Rectangle().fill(gray.opacity(0.5)).frame(width: len, height: 1)
                    .position(x: cx + gap + len / 2, y: cy)

                // Red center dot
                Circle().fill(red.opacity(0.85)).frame(width: 3, height: 3)
                    .position(x: cx, y: cy)
            }
        }
        .ignoresSafeArea()
    }
}


// MARK: - Recording Vignette

struct RecordingVignette: View {
    let red: Color
    let blinkOn: Bool

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(
                            red.opacity(blinkOn ? 0.25 : 0.08),
                            lineWidth: 3
                        )
                )
        }
    }
}


// MARK: - Compass Bar (slim)

struct CompassBar: View {
    let heading: Float
    let gray: Color
    let red: Color

    private let w: CGFloat = 260
    private let h: CGFloat = 22
    private let dpp: CGFloat = 0.9

    var body: some View {
        let headingDeg = CGFloat((heading * 180 / .pi + 360)
            .truncatingRemainder(dividingBy: 360))

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.45))
                .frame(width: w, height: h)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(gray.opacity(0.12), lineWidth: 1))

            Canvas { ctx, size in
                let cx = size.width / 2

                // Snap to nearest 5° tick, then offset by the fractional
                // remainder so ticks scroll smoothly between snaps.
                let base = floor(headingDeg / 5) * 5
                let frac = (headingDeg - base) * dpp

                for i in -30...30 {
                    let worldDeg = Int(base) + i * 5
                    let normDeg  = ((worldDeg % 360) + 360) % 360
                    let x = cx + CGFloat(i * 5) * dpp - frac
                    guard x >= 0 && x <= size.width else { continue }

                    let major = normDeg % 45 == 0
                    let mid   = normDeg % 15 == 0
                    let tickH: CGFloat = major ? 10 : (mid ? 6 : 3)
                    let alpha: Double  = major ? 0.7 : (mid ? 0.35 : 0.15)

                    var tick = Path()
                    tick.move(to:    CGPoint(x: x, y: size.height))
                    tick.addLine(to: CGPoint(x: x, y: size.height - tickH))
                    ctx.stroke(tick, with: .color(gray.opacity(alpha)),
                               lineWidth: major ? 1.2 : 0.7)

                    if major {
                        let idx = (normDeg / 45) % 8
                        let label = Text(["N","NE","E","SE","S","SW","W","NW"][idx])
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                        ctx.draw(label, at: CGPoint(x: x, y: 5))
                    }
                }
            }
            .frame(width: w, height: h)
            .foregroundColor(gray.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Red center indicator
            VStack(spacing: 0) {
                Spacer()
                Triangle().fill(red).frame(width: 5, height: 3)
            }
            .frame(height: h)

            // Bearing readout
            HStack {
                Spacer()
                Text(String(format: "%03d\u{00B0}", Int(headingDeg)))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(gray.opacity(0.6))
                    .padding(.trailing, 8)
            }
            .frame(width: w)
        }
        .frame(width: w, height: h)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

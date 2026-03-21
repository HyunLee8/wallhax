import SwiftUI
import ARKit
import Combine

// MARK: - Military Operations View

struct MilitaryOperationsView: View {
    let useCase: UseCase
    let callsign: String
    let onExit: () -> Void

    @StateObject private var arState = ARState.shared
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

    private let hue    = Color(red: 0.55, green: 0.71, blue: 0.31)
    private let hueDim = Color(red: 0.55, green: 0.71, blue: 0.31).opacity(0.45)
    private let bg     = Color.black.opacity(0.72)

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                ARViewContainer(isRecording: $isRecording)
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(false)

                TacticalReticle(trackingState: arState.trackingState, hue: hue)
                    .allowsHitTesting(false)

                if isLandscape {
                    landscapeLayout(geo: geo)
                } else {
                    portraitLayout
                }

                if showPinWheel {
                    PinWheelOverlay(
                        labels: useCase.pinLabels,
                        accentColor: hue,
                        selectedIndex: selectedPinIndex
                    )
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .zIndex(15)
                }

                if showFullMap {
                    FullMapView(
                        trajectory: arState.trajectory,
                        currentPos: SIMD2<Float>(arState.position.x, arState.position.z),
                        heading: arState.heading,
                        pins: arState.pins,
                        peers: arState.peers,
                        accentColor: hue,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showFullMap = false
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
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

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            topBar(compact: false)

            HStack(alignment: .top) {
                leftPanel(mapSize: 140)
                Spacer()
                rightPanel(compact: false)
            }
            .padding(.top, 6)

            Spacer()

            CompassStrip(heading: arState.heading, hue: hue)
                .padding(.bottom, 6)

            sendStatusBadge

            bottomControls(compact: false)
        }
        .padding(.top, 54)
    }

    // MARK: - Landscape Layout
    // No side panels — everything in slim top + bottom strips, full center clear.

    private func landscapeLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            landscapeTopStrip
            Spacer()
            sendStatusBadge
            landscapeBottomStrip
        }
    }

    private var landscapeTopStrip: some View {
        HStack(spacing: 0) {
            // EXFIL
            Button(action: { ARState.shared.reset(); onExit() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                    Text("EXFIL")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(hue)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(bg)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(hue.opacity(0.5), lineWidth: 1))
            }

            stripDivider

            // MGRS + AZM + ELEV
            HStack(spacing: 10) {
                stripStat("MGRS", mgrsCompact)
                stripDivider
                stripStat("AZM",  azimuthString)
                stripStat("ELEV", String(format: "%+.1fM", arState.position.y))
                stripStat("DIST", String(format: "%.1fM", arState.distanceWalked))
            }

            Spacer()

            // Classification
            Text("UNCLASSIFIED // FOUO")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.yellow.opacity(0.7))

            Spacer()

            // Status dots
            HStack(spacing: 8) {
                statusDot(trackingColor, "TRK:\(trackingLabel)", trackingColor)
                statusDot(arState.isRelayConnected ? hue : .red,
                          arState.isRelayConnected ? "NET:UP" : "NET:DN",
                          arState.isRelayConnected ? hue : .red)
                if isRecording {
                    statusDot(blinkOn ? .red : .red.opacity(0.2),
                              "REC \(formatElapsed(elapsed))", .red)
                }
            }

            stripDivider

            // Callsign nameplate
            VStack(alignment: .leading, spacing: 1) {
                Text("OP")
                    .font(.system(size: 6, weight: .regular, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(hueDim)
                Text(callsign.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(hue)
                    .tracking(1)
            }

            stripDivider

            // DTG
            Text(zuluTime)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(hue)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.72))
        .overlay(Rectangle().fill(hue.opacity(0.18)).frame(height: 1), alignment: .bottom)
        .padding(.top, 36)
    }

    private var landscapeBottomStrip: some View {
        HStack(alignment: .center, spacing: 0) {
            // Tiny minimap
            ZStack {
                MapCanvas(
                    trajectory: arState.trajectory,
                    currentPos: SIMD2<Float>(arState.position.x, arState.position.z),
                    heading: arState.heading,
                    pins: arState.pins,
                    peers: arState.peers,
                    scale: 90.0 / 2.0 / 8.0,
                    offset: .zero,
                    centerOnUser: true,
                    showLabels: false,
                    accentColor: hue
                )
                .frame(width: 90, height: 60)
                .background(Color(red: 0.02, green: 0.06, blue: 0.02).opacity(0.9))
                .clipShape(Rectangle())

                TacticalCornerBrackets(color: hue.opacity(0.7), size: 90,
                                       strokeWidth: 1, armLength: 10)
                    .frame(width: 90, height: 90)   // brackets are square; clip will handle it
                    .clipShape(Rectangle().size(width: 90, height: 60))

                VStack {
                    Text("N")
                        .font(.system(size: 6, weight: .black, design: .monospaced))
                        .foregroundColor(hue.opacity(0.7))
                        .padding(.top, 2)
                    Spacer()
                }
                .frame(width: 90, height: 60)
            }
            .overlay(Rectangle().stroke(hue.opacity(0.3), lineWidth: 1))
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showFullMap = true }
            }
            .padding(.trailing, 10)

            stripDivider

            // Controls
            HStack(spacing: 8) {
                controlsMark
                controlsRecord(compact: true)
                if hasRecording && !isRecording { controlsTX(compact: true) }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Compass
            CompassStrip(heading: arState.heading, hue: hue, width: 190)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 8)
        .padding(.leading, 14)
        .background(Color.black.opacity(0.72))
        .overlay(Rectangle().fill(hue.opacity(0.18)).frame(height: 1), alignment: .top)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(hue.opacity(0.25))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 8)
    }

    private func stripStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 6, weight: .regular, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(hueDim)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(hue)
        }
    }

    private var mgrsCompact: String {
        let e = Int(abs(arState.position.x) * 10) % 100000
        let n = Int(abs(arState.position.z) * 10) % 100000
        return String(format: "%05d %05d", e, n)
    }

    // MARK: - Top Bar

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 0) {
            Button(action: { ARState.shared.reset(); onExit() }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                    Text("EXFIL")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(hue)
                .padding(.horizontal, 10)
                .padding(.vertical, compact ? 4 : 6)
                .background(bg)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(hue.opacity(0.5), lineWidth: 1))
            }

            Spacer()

            Text("UNCLASSIFIED // FOUO")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.yellow.opacity(0.75))

            Spacer()

            // Callsign nameplate
            HStack(spacing: 5) {
                Rectangle().fill(hue.opacity(0.5)).frame(width: 2, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OP")
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(hueDim)
                    Text(callsign.uppercased())
                        .font(.system(size: compact ? 10 : 12, weight: .black, design: .monospaced))
                        .foregroundColor(hue)
                        .tracking(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hue.opacity(0.08))
            .overlay(Rectangle().stroke(hue.opacity(0.25), lineWidth: 1))

            Rectangle().fill(hue.opacity(0.25)).frame(width: 1, height: 18).padding(.horizontal, 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(zuluTime)
                    .font(.system(size: compact ? 11 : 14, weight: .black, design: .monospaced))
                    .foregroundColor(hue)
                Text("DTG")
                    .font(.system(size: 7, weight: .regular, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(hueDim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 5 : 7)
        .background(Color.black.opacity(0.65))
        .overlay(Rectangle().fill(hue.opacity(0.18)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Left Panel (portrait 140, landscape 100)

    private func leftPanel(mapSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                MapCanvas(
                    trajectory: arState.trajectory,
                    currentPos: SIMD2<Float>(arState.position.x, arState.position.z),
                    heading: arState.heading,
                    pins: arState.pins,
                    peers: arState.peers,
                    scale: mapSize / 2.0 / 8.0,
                    offset: .zero,
                    centerOnUser: true,
                    showLabels: false,
                    accentColor: hue
                )
                .frame(width: mapSize, height: mapSize)
                .background(Color(red: 0.02, green: 0.06, blue: 0.02).opacity(0.92))
                .clipShape(Rectangle())

                TacticalCornerBrackets(color: hue.opacity(0.8), size: mapSize)

                VStack {
                    Text("N")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(hue.opacity(0.7))
                        .padding(.top, 3)
                    Spacer()
                }
                .frame(width: mapSize, height: mapSize)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(hue.opacity(0.5))
                            .padding(4)
                    }
                }
                .frame(width: mapSize, height: mapSize)
            }
            .overlay(Rectangle().stroke(hue.opacity(0.3), lineWidth: 1))
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showFullMap = true }
            }

            // MGRS block
            tacPanel {
                VStack(alignment: .leading, spacing: 4) {
                    tacLabel("MGRS")
                    Text(mgrsString)
                        .font(.system(size: mapSize < 120 ? 10 : 12, weight: .bold, design: .monospaced))
                        .foregroundColor(hue)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Rectangle().fill(hue.opacity(0.15)).frame(height: 1)
                    HStack(spacing: 8) {
                        tacValueSmall("ELEV", String(format: "%+.1fM", arState.position.y))
                        tacValueSmall("AZM", azimuthString)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
            }
            .frame(width: mapSize)
        }
        .padding(.leading, 14)
    }

    // MARK: - Right Panel

    private func rightPanel(compact: Bool) -> some View {
        tacPanel {
            if compact {
                // Landscape: single compact column, no section headers
                VStack(alignment: .leading, spacing: 5) {
                    tacRow("DIST",  String(format: "%.1fM", arState.distanceWalked))
                    tacRow("FEAT",  "\(arState.featureCount)")
                    tacRow("MARKS", "\(arState.pins.count)")
                    Rectangle().fill(hue.opacity(0.2)).frame(height: 1)
                    statusDot(isRecording ? (blinkOn ? Color.red : Color.red.opacity(0.2)) : hueDim,
                              isRecording ? (blinkOn ? "REC \(formatElapsed(elapsed))" : "REC \(formatElapsed(elapsed))") : "ISR STBY",
                              isRecording ? .red : hueDim)
                    statusDot(trackingColor, "TRK \(trackingLabel)", trackingColor)
                    statusDot(arState.isRelayConnected ? hue : .red,
                              arState.isRelayConnected ? "NET UP" : "NET DN",
                              arState.isRelayConnected ? hue : .red)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
            } else {
                // Portrait: full panel with section headers
                VStack(alignment: .leading, spacing: 0) {
                    tacSectionHeader("OPERATOR STATUS")
                    VStack(alignment: .leading, spacing: 6) {
                        tacRow("DIST",   String(format: "%.1f M", arState.distanceWalked))
                        tacRow("FEAT",   "\(arState.featureCount) PTS")
                        tacRow("MARKS",  "\(arState.pins.count) PINS")
                        tacRow("FRAMES", "\(frameCount)")
                    }
                    .padding(.bottom, 8)

                    Rectangle().fill(hue.opacity(0.2)).frame(height: 1).padding(.vertical, 6)
                    tacSectionHeader("SYSTEMS")

                    VStack(alignment: .leading, spacing: 5) {
                        statusDot(isRecording ? (blinkOn ? Color.red : Color.red.opacity(0.2)) : hueDim,
                                  isRecording ? (blinkOn ? "ISR ● REC  \(formatElapsed(elapsed))" : "ISR ○ REC  \(formatElapsed(elapsed))") : "ISR  STANDBY",
                                  isRecording ? .red : hueDim)
                        statusDot(trackingColor, "TRK  \(trackingLabel)", trackingColor)
                        statusDot(arState.isRelayConnected ? hue : .red,
                                  "NET  \(arState.isRelayConnected ? "LINK UP" : "LINK DN")",
                                  arState.isRelayConnected ? hue : .red)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .padding(.trailing, 14)
    }

    // MARK: - Bottom Controls (portrait)

    private var bottomControls: some View { bottomControls(compact: false) }

    private func bottomControls(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            controlsMark
            controlsRecord(compact: compact)
            if hasRecording && !isRecording { controlsTX(compact: compact) }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, compact ? 0 : 44)
    }

    // MARK: - Control Atoms

    private var controlsMark: some View {
        ZStack {
            Rectangle()
                .fill(showPinWheel ? hue.opacity(0.2) : bg)
                .frame(width: 58, height: 48)
                .overlay(Rectangle().stroke(hue.opacity(showPinWheel ? 1.0 : 0.4), lineWidth: 1))
            VStack(spacing: 3) {
                Image(systemName: "mappin")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(showPinWheel ? .white : hue)
                Text("MARK")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(showPinWheel ? .white : hueDim)
            }
        }
        .scaleEffect(showPinWheel ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPinWheel)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { value in
                    switch value {
                    case .first: break
                    case .second(let longPressed, let drag):
                        if longPressed && !showPinWheel {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showPinWheel = true }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        if let drag = drag { updatePinSelection(dragLoc: drag.location) }
                    }
                }
                .onEnded { _ in
                    if showPinWheel, let idx = selectedPinIndex {
                        let label = useCase.pinLabels[idx].label
                        ARState.shared.requestDropPin?(label, UIColor(hue))
                        NetworkingManager.shared.sendPin(position: arState.position, label: label)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    withAnimation(.spring(response: 0.25)) { showPinWheel = false }
                    selectedPinIndex = nil
                }
        )
    }

    private func controlsRecord(compact: Bool) -> some View {
        Button(action: toggleRecording) {
            HStack(spacing: 8) {
                ZStack {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: 11, height: 11)
                            .opacity(blinkOn ? 1 : 0.3)
                    } else {
                        Circle().stroke(hue, lineWidth: 2).frame(width: 13, height: 13)
                        Circle().fill(hue.opacity(0.4)).frame(width: 7, height: 7)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isRecording ? "HALT ISR" : "ISR REC")
                        .font(.system(size: compact ? 10 : 12, weight: .black, design: .monospaced))
                        .tracking(1.5)
                    Text(isRecording ? formatElapsed(elapsed) : "STANDBY")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundColor(isRecording ? .red.opacity(0.85) : hueDim)
                }
            }
            .foregroundColor(isRecording ? .red : hue)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 9 : 12)
            .background(isRecording ? Color.red.opacity(0.12) : bg)
            .overlay(Rectangle().stroke(isRecording ? Color.red.opacity(0.7) : hue.opacity(0.4), lineWidth: 1))
        }
    }

    private func controlsTX(compact: Bool) -> some View {
        Button(action: sendToMac) {
            HStack(spacing: 7) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: hue))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 11, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isSending ? "TX..." : "TX INTEL")
                        .font(.system(size: compact ? 10 : 12, weight: .black, design: .monospaced))
                        .tracking(1.5)
                    Text(isSending ? "SENDING" : "UPLOAD")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundColor(hueDim)
                }
            }
            .foregroundColor(hue)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 9 : 12)
            .background(bg)
            .overlay(Rectangle().stroke(hue.opacity(0.5), lineWidth: 1))
        }
        .disabled(isSending)
    }

    // MARK: - Send Status Badge

    @ViewBuilder
    private var sendStatusBadge: some View {
        if !sendStatus.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                Text(sendStatus)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(hue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(hue.opacity(0.35), lineWidth: 1))
            .cornerRadius(3)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Computed Values

    private var mgrsString: String {
        let e = Int(abs(arState.position.x) * 10) % 100000
        let n = Int(abs(arState.position.z) * 10) % 100000
        return String(format: "18T XS %05d %05d", e, n)
    }

    private var azimuthString: String {
        let deg = (arState.heading * 180 / .pi + 360)
            .truncatingRemainder(dividingBy: 360)
        return String(format: "%03d°M", Int(deg))
    }

    private var trackingColor: Color {
        switch arState.trackingState {
        case "normal":                       return hue
        case "initializing", "relocalizing": return .yellow
        default:                             return .red
        }
    }

    private var trackingLabel: String {
        switch arState.trackingState {
        case "normal":        return "NRM"
        case "initializing":  return "INIT"
        case "slow down":     return "MOT"
        case "need features": return "FEAT"
        case "relocalizing":  return "RELOC"
        default:              return "ERR"
        }
    }

    // MARK: - Actions

    private func updateZuluTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        zuluTime = String(format: "%02d%02d%02dZ",
                          cal.component(.hour,   from: now),
                          cal.component(.minute, from: now),
                          cal.component(.second, from: now))
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
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
            let itemAngle = -Double.pi / 2 + Double(i) * step
            var diff = abs(angle - itemAngle)
            if diff > .pi { diff = 2 * .pi - diff }
            if diff < bestDiff { bestDiff = diff; best = i }
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
            sendStatus = "NO INTEL DATA"; return
        }
        isSending = true
        NetworkingManager.shared.sendToMac(sessionPath: sessionPath) { done, success, status in
            sendStatus = status
            if done { isSending = false; if success { hasRecording = false } }
        }
    }

    // MARK: - Sub-view Helpers

    private func tacPanel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .background(Color.black.opacity(0.68))
            .overlay(Rectangle().stroke(hue.opacity(0.22), lineWidth: 1))
    }

    private func tacSectionHeader(_ text: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(hue.opacity(0.5)).frame(width: 3, height: 8)
            Text(text)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(2)
                .foregroundColor(hueDim)
        }
        .padding(.bottom, 6)
    }

    private func tacRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1)
                .foregroundColor(hueDim)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(hue)
        }
    }

    private func tacLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .black, design: .monospaced))
            .tracking(2)
            .foregroundColor(hueDim)
    }

    private func tacValueSmall(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(hueDim)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(hue)
        }
    }

    private func statusDot(_ dotColor: Color, _ text: String, _ textColor: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(textColor)
                .tracking(0.5)
        }
    }
}


// MARK: - Tactical Reticle

struct TacticalReticle: View {
    let trackingState: String
    let hue: Color

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            ZStack {
                TacticalCornerBrackets(color: hue.opacity(0.55), size: 96, strokeWidth: 1.5, armLength: 18)
                    .position(x: cx, y: cy)

                Circle()
                    .stroke(hue.opacity(0.35), lineWidth: 1)
                    .frame(width: 40, height: 40)
                    .position(x: cx, y: cy)

                let gap: CGFloat = 24
                let len: CGFloat = 18
                let w:   CGFloat = 1

                Rectangle().fill(hue.opacity(0.85)).frame(width: w, height: len)
                    .position(x: cx, y: cy - gap - len / 2)
                Rectangle().fill(hue.opacity(0.85)).frame(width: w, height: len)
                    .position(x: cx, y: cy + gap + len / 2)
                Rectangle().fill(hue.opacity(0.85)).frame(width: len, height: w)
                    .position(x: cx - gap - len / 2, y: cy)
                Rectangle().fill(hue.opacity(0.85)).frame(width: len, height: w)
                    .position(x: cx + gap + len / 2, y: cy)

                Circle().fill(hue).frame(width: 3, height: 3)
                    .position(x: cx, y: cy)

                ForEach([1, 2, 3], id: \.self) { i in
                    let yOff = CGFloat(i) * 8 + gap
                    Rectangle().fill(hue.opacity(0.5)).frame(width: i == 2 ? 8 : 5, height: 0.8)
                        .position(x: cx, y: cy - yOff)
                    Rectangle().fill(hue.opacity(0.5)).frame(width: i == 2 ? 8 : 5, height: 0.8)
                        .position(x: cx, y: cy + yOff)
                }

                Text(trackingStatusLabel)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(hue.opacity(0.65))
                    .position(x: cx, y: cy + 68)
            }
        }
        .ignoresSafeArea()
    }

    private var trackingStatusLabel: String {
        switch trackingState {
        case "normal":        return "TRACKING  NRM"
        case "initializing":  return "TRACKING  INIT"
        case "slow down":     return "TRACKING  MOT"
        case "need features": return "TRACKING  FEAT"
        case "relocalizing":  return "TRACKING  RELOC"
        default:              return "TRACKING  ERR"
        }
    }
}


// MARK: - Tactical Corner Brackets

struct TacticalCornerBrackets: View {
    let color: Color
    var size: CGFloat
    var strokeWidth: CGFloat = 1.2
    var armLength: CGFloat  = 16

    var body: some View {
        Canvas { ctx, _ in
            let s   = size
            let arm = armLength
            let corners: [(CGPoint, [CGPoint])] = [
                (CGPoint(x: 0, y: 0), [CGPoint(x: arm, y: 0),   CGPoint(x: 0, y: arm)]),
                (CGPoint(x: s, y: 0), [CGPoint(x: s-arm, y: 0), CGPoint(x: s, y: arm)]),
                (CGPoint(x: 0, y: s), [CGPoint(x: arm, y: s),   CGPoint(x: 0, y: s-arm)]),
                (CGPoint(x: s, y: s), [CGPoint(x: s-arm, y: s), CGPoint(x: s, y: s-arm)])
            ]
            for (origin, arms) in corners {
                var path = Path()
                path.move(to: arms[0])
                path.addLine(to: origin)
                path.addLine(to: arms[1])
                ctx.stroke(path, with: .color(color), lineWidth: strokeWidth)
            }
        }
        .frame(width: size, height: size)
    }
}


// MARK: - Compass Strip

struct CompassStrip: View {
    let heading: Float
    let hue: Color
    var width: CGFloat = 280

    private let stripHeight: CGFloat   = 28
    private let degreesPerPoint: CGFloat = 0.9

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.68))
                .frame(width: width, height: stripHeight)
                .overlay(Rectangle().stroke(hue.opacity(0.22), lineWidth: 1))

            Canvas { ctx, size in
                let centerX  = size.width / 2
                let headingDeg = CGFloat((heading * 180 / .pi + 360)
                    .truncatingRemainder(dividingBy: 360))

                for deg in stride(from: -180, through: 180, by: 5) {
                    let d = CGFloat(deg)
                    let x = centerX + d * degreesPerPoint
                    guard x >= 0 && x <= size.width else { continue }

                    let absDeg  = Int((headingDeg + d + 360).truncatingRemainder(dividingBy: 360))
                    let isMajor = absDeg % 45 == 0
                    let isMid   = absDeg % 15 == 0
                    let tickH: CGFloat = isMajor ? 12 : (isMid ? 8 : 5)
                    let alpha: Double  = isMajor ? 0.9 : (isMid ? 0.55 : 0.3)

                    var tick = Path()
                    tick.move(to:    CGPoint(x: x, y: size.height))
                    tick.addLine(to: CGPoint(x: x, y: size.height - tickH))
                    ctx.stroke(tick, with: .color(hue.opacity(alpha)), lineWidth: isMajor ? 1.5 : 0.8)

                    if isMajor {
                        let idx   = (absDeg / 45) % 8
                        let label = Text(["N","NE","E","SE","S","SW","W","NW"][idx])
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                        ctx.draw(label, at: CGPoint(x: x, y: size.height - 22))
                    }
                }
            }
            .frame(width: width, height: stripHeight)
            .foregroundColor(hue.opacity(0.6))

            VStack(spacing: 0) {
                Triangle().fill(hue).frame(width: 6, height: 4)
                Spacer()
            }
            .frame(height: stripHeight)

            HStack {
                Spacer()
                Text(String(format: "%03d°M", Int((heading * 180 / .pi + 360)
                    .truncatingRemainder(dividingBy: 360))))
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(hue)
                    .padding(.trailing, 6)
            }
            .frame(width: width)
        }
        .frame(width: width, height: stripHeight)
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

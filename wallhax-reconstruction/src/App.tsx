import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Canvas, extend, useFrame, useThree } from '@react-three/fiber'
import { Environment, OrbitControls } from '@react-three/drei'
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib'
import * as THREE from 'three'
import { LumaSplatsThree } from '@lumaai/luma-web'
import type { ArkAlignment, TrajectoryPoint } from './types'

export type { TrajectoryPoint, ArkAlignment } from './types'

extend({ LumaSplats: LumaSplatsThree })

const ALIGNMENT_STORAGE_KEY = 'wallhax.arkitAlignment'

/**
 * Multiplies raw ARKit trajectory x/y/z so the path spans longer in space.
 * Applied to positions only — tube radius and dot size stay fixed in path space, so girth does not grow with stretch.
 * Alignment → Scale still uniformly scales the whole path group (room fit).
 */
const PATH_POSITION_SCALE = 1.75

const ALIGN_POS_MIN = -40
const ALIGN_POS_MAX = 40
const ALIGN_POS_SLIDER_STEP = 0.05
const ALIGN_POS_NUMBER_STEP = 0.001

const ALIGN_ROT_MIN = -360
const ALIGN_ROT_MAX = 360
const ALIGN_ROT_SLIDER_STEP = 0.5
const ALIGN_ROT_NUMBER_STEP = 0.01

const ALIGN_SCALE_MIN = 0.05
const ALIGN_SCALE_MAX = 12
const ALIGN_SCALE_SLIDER_STEP = 0.05
const ALIGN_SCALE_NUMBER_STEP = 0.001

function clamp(n: number, min: number, max: number): number {
  if (!Number.isFinite(n)) return min
  return Math.min(max, Math.max(min, n))
}

function clampVec3(v: [number, number, number], min: number, max: number): [number, number, number] {
  return [clamp(v[0], min, max), clamp(v[1], min, max), clamp(v[2], min, max)]
}

function defaultAlignment(): ArkAlignment {
  return { position: [0, 0, 0], rotationDeg: [0, 0, 0], scale: 1 }
}

function loadAlignment(): ArkAlignment {
  try {
    const raw = localStorage.getItem(ALIGNMENT_STORAGE_KEY)
    if (!raw) return defaultAlignment()
    const p = JSON.parse(raw) as Partial<ArkAlignment>
    return {
      position: clampVec3((p.position ?? [0, 0, 0]) as [number, number, number], ALIGN_POS_MIN, ALIGN_POS_MAX),
      rotationDeg: clampVec3(
        (p.rotationDeg ?? [0, 0, 0]) as [number, number, number],
        ALIGN_ROT_MIN,
        ALIGN_ROT_MAX,
      ),
      scale: clamp(
        typeof p.scale === 'number' && Number.isFinite(p.scale) ? p.scale : 1,
        ALIGN_SCALE_MIN,
        ALIGN_SCALE_MAX,
      ),
    }
  } catch {
    return defaultAlignment()
  }
}

function saveAlignmentToStorage(a: ArkAlignment) {
  localStorage.setItem(ALIGNMENT_STORAGE_KEY, JSON.stringify(a))
}

function alignmentMatrix(alignment: ArkAlignment): THREE.Matrix4 {
  const m = new THREE.Matrix4()
  const euler = new THREE.Euler(
    THREE.MathUtils.degToRad(alignment.rotationDeg[0]),
    THREE.MathUtils.degToRad(alignment.rotationDeg[1]),
    THREE.MathUtils.degToRad(alignment.rotationDeg[2]),
    'XYZ',
  )
  m.compose(
    new THREE.Vector3(...alignment.position),
    new THREE.Quaternion().setFromEuler(euler),
    new THREE.Vector3(alignment.scale, alignment.scale, alignment.scale),
  )
  return m
}

/** Local-space point to hold fixed in world space when alignment scale changes (path space, before group scale). */
function scalePivotLocal(trajectory: TrajectoryPoint[], currentFrame: number, out: THREE.Vector3): THREE.Vector3 {
  if (trajectory.length === 0) {
    return out.set(0, 0, 0)
  }
  const atFrame = trajectory[currentFrame]
  if (atFrame) {
    return out.copy(scalePathPosition(atFrame))
  }
  const bbox = new THREE.Box3()
  for (const p of trajectory) {
    bbox.expandByPoint(scalePathPosition(p))
  }
  return bbox.getCenter(out)
}

/** Keeps the pivot fixed in world space when uniform scale changes (same as scaling about that point in the group's local frame). */
function positionAfterScaleChange(
  prev: ArkAlignment,
  nextScale: number,
  pivotLocal: THREE.Vector3,
): [number, number, number] {
  const euler = new THREE.Euler(
    THREE.MathUtils.degToRad(prev.rotationDeg[0]),
    THREE.MathUtils.degToRad(prev.rotationDeg[1]),
    THREE.MathUtils.degToRad(prev.rotationDeg[2]),
    'XYZ',
  )
  const q = new THREE.Quaternion().setFromEuler(euler)
  const delta = new THREE.Vector3().copy(pivotLocal).multiplyScalar(prev.scale - nextScale).applyQuaternion(q)
  return [prev.position[0] + delta.x, prev.position[1] + delta.y, prev.position[2] + delta.z]
}

function scalePathPosition(p: TrajectoryPoint): THREE.Vector3 {
  return new THREE.Vector3(
    p.x * PATH_POSITION_SCALE,
    p.y * PATH_POSITION_SCALE,
    p.z * PATH_POSITION_SCALE,
  )
}

function transformTrajectoryPoint(p: TrajectoryPoint, matrix: THREE.Matrix4): THREE.Vector3 {
  return scalePathPosition(p).applyMatrix4(matrix)
}

function fitCameraToTrajectory(
  camera: THREE.Camera,
  controls: OrbitControlsImpl,
  trajectory: TrajectoryPoint[],
  matrix: THREE.Matrix4,
) {
  if (trajectory.length === 0) return

  const bbox = new THREE.Box3()
  for (const p of trajectory) {
    bbox.expandByPoint(transformTrajectoryPoint(p, matrix))
  }
  const center = new THREE.Vector3()
  bbox.getCenter(center)

  const size = new THREE.Vector3()
  bbox.getSize(size)
  const maxDim = Math.max(size.x, size.y, size.z, 0.01)
  const dist = maxDim * 1.8

  camera.position.set(center.x + dist * 0.45, center.y + dist * 0.35, center.z + dist * 0.45)
  controls.target.copy(center)
  controls.update()
}

function fitCameraToLumaDefault(camera: THREE.Camera, controls: OrbitControlsImpl) {
  controls.target.set(0, 0, 0)
  camera.position.set(4, 3, 4)
  controls.update()
}

function fitCameraToCurrentFrame(
  camera: THREE.Camera,
  controls: OrbitControlsImpl,
  trajectory: TrajectoryPoint[],
  currentFrame: number,
  matrix: THREE.Matrix4,
) {
  if (trajectory.length === 0) return
  const p = trajectory[currentFrame]
  if (!p) return

  const dot = transformTrajectoryPoint(p, matrix)

  const bbox = new THREE.Box3()
  for (const pt of trajectory) {
    bbox.expandByPoint(transformTrajectoryPoint(pt, matrix))
  }
  const size = new THREE.Vector3()
  bbox.getSize(size)
  const maxDim = Math.max(size.x, size.y, size.z, 0.01)
  const dist = Math.max(maxDim * 0.35, 0.35)

  camera.position.set(dot.x + dist * 0.45, dot.y + dist * 0.35, dot.z + dist * 0.45)
  controls.target.copy(dot)
  controls.update()
}

function isTypingInFormControl(): boolean {
  const el = document.activeElement
  if (!el) return false
  const tag = el.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true
  return el instanceof HTMLElement && el.isContentEditable
}

function CameraKeyboardPan({ orbitRef }: { orbitRef: React.RefObject<OrbitControlsImpl | null> }) {
  const { camera } = useThree()
  const keys = useRef(new Set<string>())
  const forward = useMemo(() => new THREE.Vector3(), [])
  const right = useMemo(() => new THREE.Vector3(), [])
  const up = useMemo(() => new THREE.Vector3(0, 1, 0), [])
  const move = useMemo(() => new THREE.Vector3(), [])

  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (isTypingInFormControl()) return
      keys.current.add(e.code)
    }
    const up = (e: KeyboardEvent) => {
      keys.current.delete(e.code)
    }
    const clear = () => keys.current.clear()
    window.addEventListener('keydown', down)
    window.addEventListener('keyup', up)
    window.addEventListener('blur', clear)
    return () => {
      window.removeEventListener('keydown', down)
      window.removeEventListener('keyup', up)
      window.removeEventListener('blur', clear)
    }
  }, [])

  useFrame((_, delta) => {
    const ctl = orbitRef.current
    if (!ctl || isTypingInFormControl()) return

    const k = keys.current
    const fast = k.has('ShiftLeft') || k.has('ShiftRight')
    const speed = (fast ? 2.5 : 1) * 4 * delta

    const alt = k.has('AltLeft') || k.has('AltRight')
    const arrowUp = k.has('ArrowUp')
    const arrowDown = k.has('ArrowDown')

    const mx = (k.has('KeyD') || k.has('ArrowRight') ? 1 : 0) - (k.has('KeyA') || k.has('ArrowLeft') ? 1 : 0)
    const mz =
      (k.has('KeyW') || (arrowUp && !alt) ? 1 : 0) - (k.has('KeyS') || (arrowDown && !alt) ? 1 : 0)
    const my =
      (k.has('KeyE') || k.has('PageUp') || (alt && arrowUp) ? 1 : 0) -
      (k.has('KeyQ') || k.has('PageDown') || (alt && arrowDown) ? 1 : 0)

    if (mx === 0 && mz === 0 && my === 0) return

    camera.getWorldDirection(forward)
    forward.y = 0
    if (forward.lengthSq() < 1e-10) {
      forward.set(0, 0, -1)
    } else {
      forward.normalize()
    }
    right.crossVectors(forward, up).normalize()

    move.set(0, 0, 0)
    if (mx !== 0) move.addScaledVector(right, mx * speed)
    if (mz !== 0) move.addScaledVector(forward, mz * speed)
    move.y = my * speed

    camera.position.add(move)
    ctl.target.add(move)
    ctl.update()
  })

  return null
}

type TrajectoryProps = {
  pathData: TrajectoryPoint[]
  currentFrame: number
}

const TrajectoryTube = ({ pathData, currentFrame }: TrajectoryProps) => {
  const points = useMemo(() => {
    const visiblePath = pathData.slice(0, currentFrame + 1)
    if (!visiblePath || visiblePath.length < 2) return []
    return visiblePath.map((p) => scalePathPosition(p))
  }, [pathData, currentFrame])

  const curve = useMemo(() => {
    if (points.length < 2) return null
    return new THREE.CatmullRomCurve3(points, false, 'catmullrom', 0.5)
  }, [points])

  if (!curve) return null

  return (
    <mesh renderOrder={1000}>
      <tubeGeometry args={[curve, 200, 0.12, 8, false]} />
      <meshStandardMaterial
        color="#00ffff"
        emissive="#00ffff"
        emissiveIntensity={2}
        roughness={0.2}
        depthTest={false}
        depthWrite={false}
        transparent
      />
    </mesh>
  )
}

const CurrentLocationMarker = ({ pathData, currentFrame }: TrajectoryProps) => {
  const currentPos = pathData[currentFrame]
  if (!currentPos) return null

  const pos = scalePathPosition(currentPos)
  return (
    <mesh position={[pos.x, pos.y, pos.z]} renderOrder={1001}>
      <sphereGeometry args={[0.2, 16, 16]} />
      <meshBasicMaterial color="#ff0044" depthTest={false} depthWrite={false} transparent />
    </mesh>
  )
}

function LumaInitialCamera({
  lumaRef,
  orbitRef,
  skipLumaHint,
}: {
  lumaRef: React.RefObject<LumaSplatsThree | null>
  orbitRef: React.RefObject<OrbitControlsImpl | null>
  skipLumaHint: boolean
}) {
  const { camera } = useThree()

  useEffect(() => {
    const l = lumaRef.current
    if (!l) return

    const handler = (transform: THREE.Matrix4) => {
      if (skipLumaHint) return
      const pos = new THREE.Vector3()
      const quat = new THREE.Quaternion()
      const scl = new THREE.Vector3()
      transform.decompose(pos, quat, scl)
      camera.position.copy(pos)
      camera.quaternion.copy(quat)
      const ctl = orbitRef.current
      if (ctl) {
        ctl.target.set(0, 0, 0)
        ctl.update()
      }
    }

    l.onInitialCameraTransform = handler
    return () => {
      if (l.onInitialCameraTransform === handler) l.onInitialCameraTransform = null
    }
  }, [camera, lumaRef, orbitRef, skipLumaHint])

  return null
}

function CameraFitTrajectory({
  trajectory,
  matrix,
  orbitRef,
}: {
  trajectory: TrajectoryPoint[]
  matrix: THREE.Matrix4
  orbitRef: React.RefObject<OrbitControlsImpl | null>
}) {
  const { camera } = useThree()

  // Auto-fit only when trajectory data arrives or changes — not when alignment sliders update `matrix`,
  // so nudging the path does not snap the camera. Use Fit view for a deliberate refit.
  useEffect(
    () => {
      if (trajectory.length === 0 || !orbitRef.current) return
      fitCameraToTrajectory(camera, orbitRef.current, trajectory, matrix)
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps -- omit `matrix`: alignment tweaks must not refit
    [trajectory, camera, orbitRef],
  )

  return null
}

type SceneProps = {
  trajectory: TrajectoryPoint[]
  currentFrame: number
  alignment: ArkAlignment
  fitViewRef: React.MutableRefObject<(() => void) | null>
  focusDotRef: React.MutableRefObject<(() => void) | null>
}

function Scene({ trajectory, currentFrame, alignment, fitViewRef, focusDotRef }: SceneProps) {
  const { camera } = useThree()
  const orbitRef = useRef<OrbitControlsImpl>(null)
  const lumaRef = useRef<LumaSplatsThree>(null)
  const hasTrajectory = trajectory.length > 0

  const matrix = useMemo(() => alignmentMatrix(alignment), [alignment])

  useEffect(() => {
    fitViewRef.current = () => {
      const ctl = orbitRef.current
      if (!ctl) return
      if (trajectory.length > 0) {
        fitCameraToTrajectory(camera, ctl, trajectory, matrix)
      } else {
        fitCameraToLumaDefault(camera, ctl)
      }
    }
    return () => {
      fitViewRef.current = null
    }
  }, [camera, trajectory, matrix, fitViewRef])

  useEffect(() => {
    focusDotRef.current = () => {
      const ctl = orbitRef.current
      if (!ctl || trajectory.length === 0) return
      fitCameraToCurrentFrame(camera, ctl, trajectory, currentFrame, matrix)
    }
    return () => {
      focusDotRef.current = null
    }
  }, [camera, trajectory, currentFrame, matrix, focusDotRef])

  const euler = useMemo(
    () =>
      new THREE.Euler(
        THREE.MathUtils.degToRad(alignment.rotationDeg[0]),
        THREE.MathUtils.degToRad(alignment.rotationDeg[1]),
        THREE.MathUtils.degToRad(alignment.rotationDeg[2]),
        'XYZ',
      ),
    [alignment.rotationDeg],
  )

  return (
    <>
      <ambientLight intensity={0.55} />
      <Environment preset="city" environmentIntensity={0.45} />

      <lumaSplats
        ref={lumaRef}
        source="https://lumalabs.ai/capture/18f57320-0faf-41c3-a1d8-08a11f92c9bd"
        position={[0, 0, 0]}
        renderOrder={0}
        enableThreeShaderIntegration={false}
      />

      <LumaInitialCamera lumaRef={lumaRef} orbitRef={orbitRef} skipLumaHint={hasTrajectory} />

      <group
        position={alignment.position}
        rotation={euler}
        scale={[alignment.scale, alignment.scale, alignment.scale]}
      >
        <TrajectoryTube pathData={trajectory} currentFrame={currentFrame} />
        <CurrentLocationMarker pathData={trajectory} currentFrame={currentFrame} />
      </group>

      <CameraFitTrajectory trajectory={trajectory} matrix={matrix} orbitRef={orbitRef} />
      <CameraKeyboardPan orbitRef={orbitRef} />
      <OrbitControls
        ref={orbitRef}
        makeDefault
        screenSpacePanning
        dampingFactor={0.08}
        rotateSpeed={0.85}
        zoomSpeed={1}
        panSpeed={0.85}
        minDistance={0.25}
        maxDistance={200}
        maxPolarAngle={Math.PI * 0.95}
      />
    </>
  )
}

export default function App() {
  const [trajectory, setTrajectory] = useState<TrajectoryPoint[]>([])
  const [currentFrame, setCurrentFrame] = useState(0)
  const [alignment, setAlignment] = useState<ArkAlignment>(() => loadAlignment())
  const [isPlaying, setIsPlaying] = useState(false)
  const [playbackFps, setPlaybackFps] = useState(24)
  const [calibrationOpen, setCalibrationOpen] = useState(false)
  const fitViewRef = useRef<(() => void) | null>(null)
  const focusDotRef = useRef<(() => void) | null>(null)
  const scalePivotScratch = useRef(new THREE.Vector3())

  useEffect(() => {
    fetch('/transforms.json')
      .then((res) => res.json())
      .then((data) => {
        const extractedPoints: TrajectoryPoint[] = data.frames.map((frame: { transform_matrix: number[][] }) => {
          const m = frame.transform_matrix
          return { x: m[0][3], y: m[1][3], z: m[2][3] }
        })
        setTrajectory(extractedPoints)
        setCurrentFrame(0)
      })
      .catch((err) => console.error('Failed to load transforms:', err))
  }, [])

  const lastFrame = trajectory.length > 0 ? trajectory.length - 1 : 0

  useEffect(() => {
    if (!isPlaying || trajectory.length === 0) return
    const frameMs = 1000 / playbackFps
    let last = performance.now()
    let acc = 0
    let raf = 0

    const tick = (now: number) => {
      acc += now - last
      last = now
      if (acc >= frameMs) {
        const steps = Math.floor(acc / frameMs)
        acc -= steps * frameMs
        setCurrentFrame((f) => {
          const next = Math.min(f + steps, lastFrame)
          if (next >= lastFrame) queueMicrotask(() => setIsPlaying(false))
          return next
        })
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [isPlaying, lastFrame, playbackFps, trajectory.length])

  const pausePlayback = useCallback(() => setIsPlaying(false), [])

  const updateAlignment = useCallback((patch: Partial<ArkAlignment>) => {
    setAlignment((prev) => ({ ...prev, ...patch }))
  }, [])

  const resetAlignment = useCallback(() => {
    setAlignment(defaultAlignment())
  }, [])

  const persistAlignment = useCallback(() => {
    saveAlignmentToStorage(alignment)
  }, [alignment])

  return (
    <div className="app">
      <div className="canvas-wrap">
        <Canvas camera={{ position: [2, 2, 2], fov: 50 }} dpr={[1, 1.5]}>
          <Scene
            trajectory={trajectory}
            currentFrame={currentFrame}
            alignment={alignment}
            fitViewRef={fitViewRef}
            focusDotRef={focusDotRef}
          />
        </Canvas>
      </div>

      <aside className="hud">
        <div className="hud__card">
          <h2 className="hud__title">WALLHAX RECON</h2>
          <div className="hud__meta">
            <div>OP: Neural layout fusion</div>
            <div>
              LINK: <span className="hud__status">SPLAT + ARKIT</span>
            </div>
            <div>NODES: {trajectory.length}</div>
            <div>FRAME: {currentFrame}</div>
            <div>
              PLAYBACK:{' '}
              <span style={{ color: isPlaying ? 'var(--ok)' : 'var(--text-muted)' }}>
                {isPlaying ? 'RUN' : 'IDLE'}
              </span>
            </div>
          </div>
          <p className="hud__hint">
            Static Luma splat = level geometry. Timeline = ARKit camera replay only; the room does not animate.
          </p>
          <p className="hud__hint hud__hint--compact">
            Camera: drag rotate · scroll zoom · right-drag or middle-drag pan · WASD / arrows pan (Shift faster) · Q/E
            or Alt+arrows vertical (Option+arrows on Mac) · Fit view / Focus dot — see buttons below.
          </p>
          <div className="hud__actions">
            <button type="button" className="btn btn--primary" onClick={() => fitViewRef.current?.()}>
              Fit view
            </button>
            <button
              type="button"
              className="btn"
              disabled={trajectory.length === 0}
              onClick={() => focusDotRef.current?.()}
            >
              Focus dot
            </button>
          </div>
        </div>
      </aside>

      <aside className="calibration">
        <div className="calibration__card">
          <button
            type="button"
            className="calibration__toggle"
            onClick={() => setCalibrationOpen((o) => !o)}
            aria-expanded={calibrationOpen}
          >
            <span>ALIGNMENT (ARKIT ↔ LUMA)</span>
            <span>{calibrationOpen ? '−' : '+'}</span>
          </button>
          {calibrationOpen && (
            <div className="calibration__body">
              <p style={{ fontSize: '0.68rem', color: 'var(--text-muted)', margin: '0 0 0.65rem', lineHeight: 1.45 }}>
                Nudge path until it sits on the floor. Rotation order XYZ (degrees). Scale uniformly fits the path to
                the room; path vertex spacing is stretched by {PATH_POSITION_SCALE}× for length (tube thickness stays
                the same in path units). Reset only updates sliders here; Save
                writes to this browser.
              </p>
              <div className="calibration__grid">
                {(['X', 'Y', 'Z'] as const).map((axis, i) => (
                  <label key={axis} className="calibration__row">
                    <span>Pos {axis}</span>
                    <input
                      type="range"
                      min={ALIGN_POS_MIN}
                      max={ALIGN_POS_MAX}
                      step={ALIGN_POS_SLIDER_STEP}
                      value={alignment.position[i]}
                      onChange={(e) => {
                        const v = parseFloat(e.target.value)
                        const next = [...alignment.position] as [number, number, number]
                        next[i] = clamp(v, ALIGN_POS_MIN, ALIGN_POS_MAX)
                        updateAlignment({ position: next })
                      }}
                    />
                    <input
                      className="calibration__number"
                      type="number"
                      min={ALIGN_POS_MIN}
                      max={ALIGN_POS_MAX}
                      step={ALIGN_POS_NUMBER_STEP}
                      value={alignment.position[i]}
                      onChange={(e) => {
                        const raw = e.target.value
                        if (raw === '' || raw === '-') return
                        const v = parseFloat(raw)
                        if (!Number.isFinite(v)) return
                        const next = [...alignment.position] as [number, number, number]
                        next[i] = clamp(v, ALIGN_POS_MIN, ALIGN_POS_MAX)
                        updateAlignment({ position: next })
                      }}
                    />
                  </label>
                ))}
                {(['X', 'Y', 'Z'] as const).map((axis, i) => (
                  <label key={`r${axis}`} className="calibration__row">
                    <span>Rot {axis}°</span>
                    <input
                      type="range"
                      min={ALIGN_ROT_MIN}
                      max={ALIGN_ROT_MAX}
                      step={ALIGN_ROT_SLIDER_STEP}
                      value={alignment.rotationDeg[i]}
                      onChange={(e) => {
                        const v = parseFloat(e.target.value)
                        const next = [...alignment.rotationDeg] as [number, number, number]
                        next[i] = clamp(v, ALIGN_ROT_MIN, ALIGN_ROT_MAX)
                        updateAlignment({ rotationDeg: next })
                      }}
                    />
                    <input
                      className="calibration__number"
                      type="number"
                      min={ALIGN_ROT_MIN}
                      max={ALIGN_ROT_MAX}
                      step={ALIGN_ROT_NUMBER_STEP}
                      value={alignment.rotationDeg[i]}
                      onChange={(e) => {
                        const raw = e.target.value
                        if (raw === '' || raw === '-') return
                        const v = parseFloat(raw)
                        if (!Number.isFinite(v)) return
                        const next = [...alignment.rotationDeg] as [number, number, number]
                        next[i] = clamp(v, ALIGN_ROT_MIN, ALIGN_ROT_MAX)
                        updateAlignment({ rotationDeg: next })
                      }}
                    />
                  </label>
                ))}
                <label className="calibration__row">
                  <span>Scale</span>
                  <input
                    type="range"
                    min={ALIGN_SCALE_MIN}
                    max={ALIGN_SCALE_MAX}
                    step={ALIGN_SCALE_SLIDER_STEP}
                    value={alignment.scale}
                    onChange={(e) => {
                      const nextScale = clamp(parseFloat(e.target.value), ALIGN_SCALE_MIN, ALIGN_SCALE_MAX)
                      setAlignment((prev) => {
                        if (prev.scale === nextScale) return prev
                        const pivot = scalePivotLocal(trajectory, currentFrame, scalePivotScratch.current)
                        return {
                          ...prev,
                          scale: nextScale,
                          position: positionAfterScaleChange(prev, nextScale, pivot),
                        }
                      })
                    }}
                  />
                  <input
                    className="calibration__number"
                    type="number"
                    min={ALIGN_SCALE_MIN}
                    max={ALIGN_SCALE_MAX}
                    step={ALIGN_SCALE_NUMBER_STEP}
                    value={alignment.scale}
                    onChange={(e) => {
                      const raw = e.target.value
                      if (raw === '' || raw === '-') return
                      const v = parseFloat(raw)
                      if (!Number.isFinite(v)) return
                      const nextScale = clamp(v, ALIGN_SCALE_MIN, ALIGN_SCALE_MAX)
                      setAlignment((prev) => {
                        if (prev.scale === nextScale) return prev
                        const pivot = scalePivotLocal(trajectory, currentFrame, scalePivotScratch.current)
                        return {
                          ...prev,
                          scale: nextScale,
                          position: positionAfterScaleChange(prev, nextScale, pivot),
                        }
                      })
                    }}
                  />
                </label>
              </div>
              <div className="calibration__actions">
                <button type="button" className="btn" onClick={resetAlignment}>
                  Reset
                </button>
                <button type="button" className="btn btn--primary" onClick={persistAlignment}>
                  Save
                </button>
              </div>
            </div>
          )}
        </div>
      </aside>

      <div className="timeline">
        <div className="timeline__card">
          <div className="timeline__row">
            <span className="timeline__label">TIMELINE</span>
            <span className="timeline__frame">
              FRAME <strong>{currentFrame}</strong> / {lastFrame}
            </span>
          </div>
          <div className="timeline__playback">
            <button
              type="button"
              className="btn btn--primary"
              disabled={trajectory.length === 0 || isPlaying}
              onClick={() => {
                if (currentFrame >= lastFrame) setCurrentFrame(0)
                setIsPlaying(true)
              }}
            >
              Play
            </button>
            <button
              type="button"
              className="btn"
              disabled={trajectory.length === 0 || !isPlaying}
              onClick={pausePlayback}
            >
              Stop
            </button>
            <button
              type="button"
              className="btn"
              disabled={trajectory.length === 0}
              onClick={() => {
                pausePlayback()
                setCurrentFrame(0)
              }}
            >
              Frame 0
            </button>
            <button
              type="button"
              className="btn"
              disabled={trajectory.length === 0}
              onClick={() => {
                pausePlayback()
                setCurrentFrame(lastFrame)
              }}
            >
              Last
            </button>
            <div className="timeline__speed">
              <label htmlFor="fps">Speed</label>
              <select
                id="fps"
                value={playbackFps}
                onChange={(e) => setPlaybackFps(Number(e.target.value))}
                disabled={trajectory.length === 0}
              >
                <option value={12}>12 fps</option>
                <option value={24}>24 fps</option>
                <option value={30}>30 fps</option>
                <option value={60}>60 fps</option>
              </select>
            </div>
          </div>
          <input
            className="timeline__range"
            type="range"
            min={0}
            max={lastFrame}
            value={currentFrame}
            onPointerDown={pausePlayback}
            onChange={(e) => {
              pausePlayback()
              setCurrentFrame(parseInt(e.target.value, 10))
            }}
          />
          <p className="timeline__hint">Scrub pauses playback. Stop freezes replay; Frame 0 / Last jump the path.</p>
        </div>
      </div>
    </div>
  )
}

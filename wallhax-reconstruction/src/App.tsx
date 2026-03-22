import { useEffect, useMemo, useState } from 'react'
import { Canvas, extend } from '@react-three/fiber'
import { OrbitControls, Environment } from '@react-three/drei'
import * as THREE from 'three'
import { LumaSplatsThree } from '@lumaai/luma-web'

// Register Luma WebGL component with React Three Fiber
extend({ LumaSplats: LumaSplatsThree })

declare module '@react-three/fiber' {
  interface IntrinsicElements {
    lumaSplats: any
  }
}

const TrajectoryTube = ({ pathData, currentFrame }) => {
  const points = useMemo(() => {
    const visiblePath = pathData.slice(0, currentFrame + 1)
    if (!visiblePath || visiblePath.length < 2) return []
    return visiblePath.map(p => new THREE.Vector3(p.x, p.y, p.z))
  }, [pathData, currentFrame])

  const curve = useMemo(() => {
    if (points.length < 2) return null
    return new THREE.CatmullRomCurve3(points, false, 'catmullrom', 0.5)
  }, [points])

  if (!curve) return null

  return (
    <mesh>
      <tubeGeometry args={[curve, 200, 0.005, 8, false]} />
      <meshStandardMaterial color="#00ffff" emissive="#00ffff" emissiveIntensity={2} roughness={0.2} />
    </mesh>
  )
}

const CurrentLocationMarker = ({ pathData, currentFrame }) => {
  const currentPos = pathData[currentFrame]
  if (!currentPos) return null

  return (
    <mesh position={[currentPos.x, currentPos.y, currentPos.z]}>
      <sphereGeometry args={[0.02, 16, 16]} />
      <meshBasicMaterial color="#ff0044" />
    </mesh>
  )
}

export default function App() {
  const [trajectory, setTrajectory] = useState([])
  const [currentFrame, setCurrentFrame] = useState(0)

  // Load the ARKit data on mount
  useEffect(() => {
    fetch('/transforms.json')
      .then(res => res.json())
      .then(data => {
        const extractedPoints = data.frames.map((frame: any) => {
          const m = frame.transform_matrix
          return { x: m[0][3], y: m[1][3], z: m[2][3] }
        })
        setTrajectory(extractedPoints)
        setCurrentFrame(extractedPoints.length - 1)
      })
      .catch(err => console.error("Failed to load transforms:", err))
  }, [])

  return (
    <div style={{ width: '100vw', height: '100vh', backgroundColor: '#050505', position: 'relative', fontFamily: 'monospace' }}>

      <Canvas camera={{ position: [2, 2, 2], fov: 50 }}>
        <ambientLight intensity={0.5} />
        <Environment preset="city" />

        <group scale={1} position={[0, 0, 0]}>
          <TrajectoryTube pathData={trajectory} currentFrame={currentFrame} />
          <CurrentLocationMarker pathData={trajectory} currentFrame={currentFrame} />
        </group>

        <lumaSplats
          source="https://lumalabs.ai/capture/YOUR_URL_HERE"
          position={[0, 0, 0]}
        />

        <OrbitControls makeDefault />
      </Canvas>

      <div style={{
        position: 'absolute', top: 20, left: 20,
        color: '#00ffff', textShadow: '0 0 5px #00ffff',
        backgroundColor: 'rgba(0, 20, 20, 0.7)', padding: '15px',
        borderRadius: '8px', border: '1px solid #00ffff'
      }}>
        <h2 style={{ margin: '0 0 10px 0', fontSize: '1.2rem', tracking: '2px' }}>WALLHAX RECON</h2>
        <div style={{ fontSize: '0.9rem', lineHeight: '1.5' }}>
          <div>OP: Search & Rescue Layout</div>
          <div>STATUS: <span style={{ color: '#00ff00' }}>DATA ACQUIRED</span></div>
          <div>NODES: {trajectory.length}</div>
        </div>
      </div>

      <div style={{
        position: 'absolute', bottom: 40, left: '10%', right: '10%',
        backgroundColor: 'rgba(0, 20, 20, 0.8)', padding: '20px',
        borderRadius: '12px', border: '1px solid #00ffff',
        color: '#00ffff', backdropFilter: 'blur(5px)'
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '15px', fontWeight: 'bold' }}>
          <span>MISSION TIMELINE</span>
          <span>T-MARK: {currentFrame}</span>
        </div>

        <input
          type="range"
          min="0"
          max={trajectory.length > 0 ? trajectory.length - 1 : 0}
          value={currentFrame}
          onChange={(e) => setCurrentFrame(parseInt(e.target.value))}
          style={{
            width: '100%',
            cursor: 'pointer',
            accentColor: '#ff0044'
          }}
        />
      </div>

    </div>
  )
}

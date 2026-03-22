import { useState, useRef } from 'react'
import * as THREE from 'three';
import * as GaussianSplats3D from '@mkkellogg/gaussian-splats-3d';

function App() {
  const mountRef = useRef(null)

  useEffect(() => {
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(65, window.innerWidth / window.innerHeight, 0.1, 500);
    camera.position.set(0, 2, 5);

    const renderer = new THREE.WebGLRenderer({ antialias: false });
    renderer.setSize(window.innerWidth, window.innerHeight);

    if (mountRef.current) {
      mountRef.current.appendChild(renderer.domElement);
    }

    // Initialize the Splat Viewer
    const viewer = new GaussianSplats3D.Viewer({
      camera: camera,
      renderer: renderer,
      scene: scene,
      initialCameraPosition: [0, 2, 5],
      initialCameraLookAt: [0, 0, 0],
      halfPrecisionVideoTexture: true
    });

    viewer.addSplatScene('/mission_data/splat.ply', {
      'showLoadingUI': true,
      'position': [0, 0, 0],
      'rotation': [0, 0, 0, 1]
    }).then(() => {
      viewer.start();
    });

    // Handle Window Resize
    const handleResize = () => {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
    };
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      if (mountRef.current && renderer.domElement) {
        mountRef.current.removeChild(renderer.domElement);
      }
      viewer.dispose();
      renderer.dispose();
    };
  }, []);

  return (
    <>
      <div style={{ width: '100vw', height: '100vh', backgroundColor: '#000' }}>
        <div ref={mountRef} style={{ width: '100%', height: '100%' }} />

        <div style={{ position: 'absolute', top: 20, left: 20, color: '#00ffcc', fontFamily: 'monospace' }}>
          <h1>WallHax // Tactical Viewer</h1>
        </div>
      </div>
    </>
  )
}

export default App

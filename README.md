# wallhax - First place AI & Data science Hoo Hacks

Multi-device AR collaboration for iOS: devices stream camera pose over the network while a Mac relay forwards packets to peers and shows live trajectories. The app supports operation layouts for military, search and rescue, and firefighter scenarios (see `wallhax/UseCase.swift` and `wallhax/operations_layout/`).

A separate **web viewer** (`wallhax-reconstruction/`) overlays ARKit camera trajectories on a **Luma** Gaussian splat of the space: load trajectory `transforms.json` from the mapping pipeline, point the viewer at your Luma capture, align the path to the splat with sliders, and scrub or play back the timeline in the browser.

## Repository layout

| Path | Purpose |
|------|---------|
| `wallhax/` | SwiftUI / ARKit iOS app (Xcode target) |
| `wallhax-reconstruction/` | React + Vite viewer: Luma splats + `transforms.json` trajectory, alignment UI, playback |
| `server/` | UDP/TCP relay (`main.py`) and matplotlib visualizer (`visualizer.py`) |
| `mapping/` | Dataset tools: XMP → `transforms.json`, TCP receiver for phone → Mac scan export |
| `requirements.txt` | Python dependencies for the server and visualizer |

## Web reconstruction viewer (`wallhax-reconstruction/`)

Stack: **React 19**, **TypeScript**, **Vite**, **Three.js** with **@react-three/fiber** / **drei**, and **@lumaai/luma-web** for splat rendering.

From `wallhax-reconstruction/`:

```bash
npm install
npm run dev
```

Then open the URL Vite prints (typically `http://localhost:5173`).

Behavior:

- Fetches **`/transforms.json`** from `public/transforms.json` at load time and builds a camera path from each frame’s `transform_matrix` translation column.
- Renders a **hosted Luma capture** as the static scene; **timeline playback only moves the trajectory** (the splat does not animate). Replace the `source` URL on the `<lumaSplats>` element in `src/App.tsx` with your own Luma capture if needed.
- **Alignment (ARKit ↔ Luma)**: position, rotation (XYZ degrees), and scale sliders; **Save** persists to `localStorage` for this origin. Use this to line the path up with the floor and room.
- **Timeline**: scrub, Play / Stop, jump to first or last frame, and choose playback FPS (12–60).

Production build:

```bash
npm run build
```

Preview the production bundle with `npm run preview`.

## iOS app

1. Open `wallhax.xcodeproj` in Xcode.
2. Build and run on a **physical iPhone or iPad** (ARKit is not supported in the simulator for world tracking).

To point the client at a known relay host instead of UDP broadcast discovery, set `staticServerIP` in `wallhax/NetworkingManager.swift` (optional; `nil` uses broadcast).

## Python relay server

Install dependencies from the repo root:

```bash
pip install -r requirements.txt
```

Start the relay (from the `server/` directory):

```bash
cd server && python3 main.py
```

Behavior:

- **UDP `9876`** — Clients send pose and discovery packets. The server responds to `type: discover` with `hello` and a `mission_id`, and forwards other JSON packets between registered peers.
- **TCP `9878`** — Length-prefixed JSON for richer events (e.g. detected planes, pins); messages are forwarded to other connected clients.
- A **matplotlib** window shows each client’s trajectory and updates as packets arrive.

## Mapping and datasets

### Receive scan data from the phone

On your Mac, **before** tapping **Send to Mac** in the app:

```bash
cd mapping && python3 receive_scan.py
```

This listens on **TCP `9877`** and writes files under `mapping/data/<mission_id>/<client_id>/`. (Run from `mapping/` so paths match the script’s `OUTPUT_DIR`.)

### Build `transforms.json` for the trajectory

After you have imagery and matching `.xmp` sidecars under `mapping/data/<mission>/` (per-client subfolders), merge them into a processed dataset:

```bash
cd mapping && python3 build_mission_dataset.py --mission <mission_id>
```

Output goes to `mapping/processed/<mission>/` (`transforms.json`, `images/`). The script applies an ARKit → OpenCV-style axis conversion for a consistent export. Copy or symlink the resulting `transforms.json` into `wallhax-reconstruction/public/transforms.json` to drive camera replay in the web viewer.

**3D reconstruction** of the space is done in **Luma** (luma.ai). Create a Luma capture from your photos or video, then set that capture’s URL as the `source` on the `<lumaSplats>` element in `src/App.tsx`. The splat is static in the viewer; only the ARKit path animates during playback.

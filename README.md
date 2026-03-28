# WallHax

### 1st Place AI & Data Science — Hoo Hacks

Multiple iPhones map a space together in real-time using ARKit. Each device streams its camera pose over the network to a Mac relay, which forwards everything to connected peers and visualizes live trajectories. We built operation layouts for military, search & rescue, and firefighter scenarios — the idea is you walk through a building and everyone on the team sees where everyone else is and has been.

A separate web viewer overlays the recorded camera paths on a Luma Gaussian splat of the space so you can scrub through the timeline after the fact.

<p align="center">
  <img src="mapper1.gif" width="260" />
  <img src="mapper2.gif" width="260" />
  <img src="mapper3.gif" width="260" />
</p>

> [Devpost](https://devpost.com/software/wallhax-896ck3?ref_content=user-portfolio&ref_feature=in_progress) · [Demo Video](https://www.youtube.com/watch?v=II26dfXLtV0)

## Setup

### iOS App

1. Open `wallhax.xcodeproj` in Xcode.
2. Build and run on a **physical iPhone or iPad** (ARKit requires a real device).

### Web Viewer

```bash
cd wallhax-reconstruction
npm install
npm run dev
```

### Relay Server

```bash
pip install -r requirements.txt
cd server && python3 main.py
```

# WallHax

### 1st Place AI & Data Science — Hoo Hacks

Multi-device AR collaboration for iOS: devices stream camera pose over the network while a Mac relay forwards packets to peers and shows live trajectories.

[![WallHax](https://d112y698adiu2z.cloudfront.net/photos/production/software_photos/004/483/415/datas/gallery.jpg)](https://devpost.com/software/wallhax-896ck3?ref_content=user-portfolio&ref_feature=in_progress)

[![Demo Video](https://img.youtube.com/vi/II26dfXLtV0/maxresdefault.jpg)](https://www.youtube.com/watch?v=II26dfXLtV0)

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

### Python Relay Server

```bash
pip install -r requirements.txt
cd server && python3 main.py
```

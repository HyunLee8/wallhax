# WallHax

<p align="center">
  <img src="mapper1.gif" width="49%" />
  <img src="mapper2.gif" width="49%" />
</p>
<p align="center">
  <img src="mapper3.gif" width="100%" />
</p>

> [Devpost](https://devpost.com/software/wallhax-896ck3?ref_content=user-portfolio&ref_feature=in_progress) · [Demo Video](https://www.youtube.com/watch?v=II26dfXLtV0)

## Setup

### iOS App

1. Open `wallhax.xcodeproj` in Xcode.
2. Build and run on a **physical iPhone or iPad** (ARKit requires a real device, preferably one with a lidar scanner such as the one in the pro models).

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

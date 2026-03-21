#!/usr/bin/env python3
"""
visualizer.py — Multi-client real-time 3D map visualizer for WallHax
"""

import threading
import time
import numpy as np
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from collections import deque
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

MAX_TRAJECTORY_POINTS = 5000
CLIENT_TIMEOUT = 3.0

CLIENT_COLORS = [
    '#E8655A',  # warm coral
    '#5B8ED6',  # blue
    '#AB47BC',  # purple
    '#26C6DA',  # cyan
    '#FF7043',  # deep orange
    '#8BC34A',  # light green
]

C_ORIGIN = '#66BB6A'
C_LABEL = '#888888'


class ClientState:
    def __init__(self):
        self.trajectory: deque = deque(maxlen=MAX_TRAJECTORY_POINTS)
        self.tracking_state: str = 'waiting...'
        self.origin_locked: bool = False
        self.last_seen: float = time.time()


class Visualizer:
    def __init__(self):
        plt.rcParams.update({
            'figure.facecolor': '#FFFFFF',
            'axes.facecolor': '#FAFAFA',
            'axes.edgecolor': '#E0E0E0',
            'axes.labelcolor': '#555555',
            'axes.grid': True,
            'grid.color': '#F0F0F0',
            'grid.linewidth': 0.5,
            'text.color': '#333333',
            'xtick.color': '#999999',
            'ytick.color': '#999999',
            'font.family': 'sans-serif',
            'font.size': 9,
        })

        plt.ion()
        self._fig = plt.figure(figsize=(14, 9))
        self._fig.canvas.manager.set_window_title("WallHax — Mapping")
        self._ax = self._fig.add_axes([0.05, 0.08, 0.65, 0.85], projection='3d')
        self._ax_top = self._fig.add_axes([0.72, 0.52, 0.26, 0.40])
        self._ax_top.set_aspect('equal')
        self._ax_side = self._fig.add_axes([0.72, 0.08, 0.26, 0.40])
        self._ax_side.set_aspect('equal')

        self._clients: dict[str, ClientState] = {}
        self._client_colors: dict[str, str] = {}
        self._pins: list[tuple[list, str]] = []
        self._planes: dict[str, dict] = {}  # plane_id -> plane data (persistent)
        self._lock = threading.Lock()

    def add_pin(self, position: list, label: str):
        with self._lock:
            self._pins.append((position, label))

    def update_planes(self, client_id: str, planes: list) -> None:
        with self._lock:
            for plane in planes:
                pid = plane.get('id')
                if pid:
                    self._planes[pid] = {**plane, '_client_id': client_id}

    def update(self, client_id: str, position: list,
               tracking_state: str, origin_locked: bool):
        with self._lock:
            if client_id not in self._clients:
                idx = len(self._clients)
                self._clients[client_id] = ClientState()
                self._client_colors[client_id] = CLIENT_COLORS[idx % len(CLIENT_COLORS)]
            state = self._clients[client_id]
            state.trajectory.append(position)
            state.tracking_state = tracking_state
            state.origin_locked = origin_locked
            state.last_seen = time.time()

    def render(self):
        with self._lock:
            cutoff = time.time() - CLIENT_TIMEOUT
            stale = [cid for cid, s in self._clients.items() if s.last_seen < cutoff]
            for cid in stale:
                del self._clients[cid]
                del self._client_colors[cid]

            snapshot = {
                cid: (
                    np.array(list(s.trajectory)) if s.trajectory else np.empty((0, 3)),
                    s.tracking_state,
                    s.origin_locked,
                )
                for cid, s in self._clients.items()
            }
            client_colors = dict(self._client_colors)
            pins = list(self._pins)
            planes_snapshot = dict(self._planes)

        ax, ax_top, ax_side, fig = self._ax, self._ax_top, self._ax_side, self._fig

        ax.cla()
        ax.set_facecolor('#FAFAFA')
        ax.xaxis.pane.fill = False
        ax.yaxis.pane.fill = False
        ax.zaxis.pane.fill = False
        ax.xaxis.pane.set_edgecolor('#E8E8E8')
        ax.yaxis.pane.set_edgecolor('#E8E8E8')
        ax.zaxis.pane.set_edgecolor('#E8E8E8')
        ax.grid(True, alpha=0.3, color='#CCCCCC', linewidth=0.4)
        ax.set_xlabel('X (m)', fontsize=8, labelpad=8, color=C_LABEL)
        ax.set_ylabel('Z (m)', fontsize=8, labelpad=8, color=C_LABEL)
        ax.set_zlabel('Y (m)', fontsize=8, labelpad=8, color=C_LABEL)
        ax.tick_params(labelsize=7, colors='#AAAAAA')

        ax_top.cla()
        ax_top.set_facecolor('#FAFAFA')
        ax_top.grid(True, alpha=0.2, color='#DDDDDD', linewidth=0.4)
        ax_top.set_title('Top Down', fontsize=8, color=C_LABEL, pad=6)
        ax_top.set_xlabel('X', fontsize=7, color=C_LABEL)
        ax_top.set_ylabel('Z', fontsize=7, color=C_LABEL)
        ax_top.tick_params(labelsize=6, colors='#BBBBBB')

        ax_side.cla()
        ax_side.set_facecolor('#FAFAFA')
        ax_side.grid(True, alpha=0.2, color='#DDDDDD', linewidth=0.4)
        ax_side.set_title('Side View', fontsize=8, color=C_LABEL, pad=6)
        ax_side.set_xlabel('X', fontsize=7, color=C_LABEL)
        ax_side.set_ylabel('Y', fontsize=7, color=C_LABEL)
        ax_side.tick_params(labelsize=6, colors='#BBBBBB')

        all_trajs = []
        total_path = 0
        any_locked = False

        for cid, (traj, tracking, locked) in snapshot.items():
            color = client_colors[cid]
            total_path += traj.shape[0]
            if locked:
                any_locked = True

            if traj.shape[0] >= 2:
                ax.plot(traj[:, 0], traj[:, 2], traj[:, 1],
                        c=color, linewidth=1.8, alpha=0.9)
            if traj.shape[0] > 0:
                ax.scatter(traj[-1, 0], traj[-1, 2], traj[-1, 1],
                           c=color, s=60, edgecolors='white',
                           linewidths=1.5, zorder=5, alpha=0.95)
                all_trajs.append(traj)

            if traj.shape[0] >= 2:
                ax_top.plot(traj[:, 0], traj[:, 2], c=color, linewidth=1.2, alpha=0.8)
            if traj.shape[0] > 0:
                ax_top.scatter(traj[-1, 0], traj[-1, 2], c=color, s=30,
                               edgecolors='white', linewidths=1, zorder=5)

            if traj.shape[0] >= 2:
                ax_side.plot(traj[:, 0], traj[:, 1], c=color, linewidth=1.2, alpha=0.8)
            if traj.shape[0] > 0:
                ax_side.scatter(traj[-1, 0], traj[-1, 1], c=color, s=30,
                               edgecolors='white', linewidths=1, zorder=5)

        if any_locked:
            ax.scatter(0, 0, 0, c=C_ORIGIN, s=100, marker='^',
                       edgecolors='#2E7D32', linewidths=1.2, zorder=6)

        for plane in planes_snapshot.values():
            color = client_colors.get(plane.get('_client_id', ''), '#AAAAAA')
            try:
                t = np.array(plane['transform'], dtype=float).reshape(4, 4)
                center = np.array(plane['center'], dtype=float)
                extent = plane['extent']
                half_w, half_h = extent[0] / 2, extent[1] / 2
                x_axis = t[0, :3]
                z_axis = t[2, :3]
                corners = np.array([
                    center + half_w * x_axis + half_h * z_axis,
                    center + half_w * x_axis - half_h * z_axis,
                    center - half_w * x_axis - half_h * z_axis,
                    center - half_w * x_axis + half_h * z_axis,
                ])
                # swap Y↔Z for Y-up display in matplotlib 3D
                corners_3d = corners[:, [0, 2, 1]]
                alpha = 0.18 if plane.get('alignment') == 'horizontal' else 0.12
                poly3d = Poly3DCollection([corners_3d], alpha=alpha,
                                         facecolor=color, edgecolor=color,
                                         linewidth=0.5, zorder=2)
                ax.add_collection3d(poly3d)
                ax_top.fill(corners[:, 0], corners[:, 2],
                            color=color, alpha=alpha * 0.7, linewidth=0.4)
                ax_side.fill(corners[:, 0], corners[:, 1],
                             color=color, alpha=alpha * 0.7, linewidth=0.4)
            except (KeyError, ValueError):
                continue

        for pos, label in pins:
            ax.scatter(pos[0], pos[2], pos[1], c='#FF9800', s=80, marker='v',
                       edgecolors='#E65100', linewidths=1.0, zorder=7)
            ax.text(pos[0], pos[2], pos[1], f' {label}', fontsize=7, color='#FF9800')
            ax_top.scatter(pos[0], pos[2], c='#FF9800', s=40, marker='v',
                           edgecolors='#E65100', linewidths=0.8, zorder=7)
            ax_top.annotate(label, (pos[0], pos[2]), fontsize=6, color='#FF9800',
                            xytext=(4, 4), textcoords='offset points')
            ax_side.scatter(pos[0], pos[1], c='#FF9800', s=40, marker='v',
                            edgecolors='#E65100', linewidths=0.8, zorder=7)

        if all_trajs:
            combined = np.vstack(all_trajs)
            mid = combined.mean(axis=0)
            span = max((combined.max(axis=0) - combined.min(axis=0)).max() / 2, 1.0)
            ax.set_xlim(mid[0] - span, mid[0] + span)
            ax.set_ylim(mid[2] - span, mid[2] + span)  # ARKit Z → matplotlib Y
            ax.set_zlim(mid[1] - span, mid[1] + span)  # ARKit Y → matplotlib Z

        n_clients = len(snapshot)
        stats_str = f"Clients: {n_clients}  Path: {total_path:,}  Planes: {len(planes_snapshot)}  Pins: {len(pins)}"
        origin_str = "Origin: LOCKED" if any_locked else "Origin: searching"

        fig.text(0.05, 0.96, "WALLHAX", fontsize=14, fontweight='bold',
                 color='#333333', fontfamily='sans-serif', transform=fig.transFigure)
        fig.text(0.16, 0.965, "MAPPING", fontsize=10, fontweight='light',
                 color='#999999', fontfamily='sans-serif', transform=fig.transFigure)
        fig.text(0.05, 0.02, stats_str, fontsize=8, color='#AAAAAA',
                 fontfamily='monospace', transform=fig.transFigure)
        fig.text(0.55, 0.02, origin_str, fontsize=8,
                 color='#66BB6A' if any_locked else '#FFAB40',
                 fontfamily='monospace', transform=fig.transFigure)

        plt.pause(0.05)

        for txt in fig.texts:
            txt.remove()

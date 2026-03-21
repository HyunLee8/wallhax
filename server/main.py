#!/usr/bin/env python3
"""
relay.py — UDP relay server for WallHax multi-device AR

Forwards each client's pose packet to all other active clients,
and visualizes all clients' trajectories.

Usage:
    python relay.py
"""

import socket
import json
import queue
import threading
import time
import uuid
from typing import List, Tuple

from visualizer import Visualizer

UDP_PORT = 9876
CLIENT_TIMEOUT = 3.0


class ClientRegistry:
    def __init__(self):
        self.clients: dict[bytes, dict] = {}

    def register(self, addr: bytes, client_id: str):
        self.clients[addr] = {'client_id': client_id, 'last_seen': time.time()}

    def others(self, addr: bytes) -> List[bytes]:
        cutoff = time.time() - CLIENT_TIMEOUT
        return [a for a, info in self.clients.items()
                if a != addr and info['last_seen'] >= cutoff]

    def prune(self):
        cutoff = time.time() - CLIENT_TIMEOUT
        self.clients = {a: info for a, info in self.clients.items()
                        if info['last_seen'] >= cutoff}


def main():
    mission_id = str(uuid.uuid4())
    print(f"[relay] Mission ID: {mission_id}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('', UDP_PORT))
    print(f"[relay] Listening on :{UDP_PORT}")

    pkt_queue: queue.Queue[tuple[bytes, tuple]] = queue.Queue()

    def recv_loop():
        while True:
            data, addr = sock.recvfrom(65536)
            pkt_queue.put((data, addr))

    threading.Thread(target=recv_loop, daemon=True).start()

    registry = ClientRegistry()
    vis = Visualizer()
    packet_count = 0

    print("[relay] Visualizer ready. Waiting for devices...\n")

    while True:
        while not pkt_queue.empty():
            data, addr = pkt_queue.get_nowait()
            try:
                payload = json.loads(data.decode('utf-8'))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue

            if payload.get('type') == 'discover':
                hello = json.dumps({"type": "hello", "mission_id": mission_id}).encode()
                sock.sendto(hello, addr)
                continue

            client_id = payload.get('client_id', str(addr))
            registry.register(addr, client_id)
            registry.prune()

            for dest in registry.others(addr):
                sock.sendto(data, dest)

            if payload.get('type') == 'pin':
                vis.add_pin(payload.get('position', [0, 0, 0]), payload.get('label', ''))
                continue

            pos = payload.get('position', [0, 0, 0])
            tracking = payload.get('tracking_state', 'unknown')
            origin = payload.get('origin_locked', False)

            vis.update(client_id, pos, tracking, origin)

            packet_count += 1
            if packet_count % 20 == 1:
                n_clients = len(registry.clients)
                print(f"  pkts: {packet_count}  |  clients: {n_clients}  |  "
                      f"last: {client_id[:8]}  |  tracking: {tracking}  |  "
                      f"origin: {'YES' if origin else '-'}")

        vis.render()


if __name__ == '__main__':
    main()

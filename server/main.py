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
import struct
import threading
import time
import uuid
from typing import List, Tuple

from visualizer import Visualizer

UDP_PORT = 9876
TCP_EVENT_PORT = 9878
CLIENT_TIMEOUT = 3.0


class TCPSessionRegistry:
    def __init__(self):
        self._sessions: dict[str, tuple[socket.socket, threading.Lock]] = {}
        self._lock = threading.Lock()

    def register(self, client_id: str, conn: socket.socket) -> None:
        with self._lock:
            self._sessions[client_id] = (conn, threading.Lock())

    def unregister(self, client_id: str) -> None:
        with self._lock:
            self._sessions.pop(client_id, None)

    def forward(self, sender_client_id: str, data: bytes) -> None:
        with self._lock:
            peers = [(conn, lock) for cid, (conn, lock) in self._sessions.items()
                     if cid != sender_client_id]
        for conn, lock in peers:
            try:
                with lock:
                    _send_tcp_packet(conn, data)
            except OSError:
                pass


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

    def others_by_client_id(self, sender_client_id: str) -> List[tuple]:
        cutoff = time.time() - CLIENT_TIMEOUT
        return [a for a, info in self.clients.items()
                if info['client_id'] != sender_client_id and info['last_seen'] >= cutoff]


def _recv_exact_tcp(sock: socket.socket, n: int) -> bytes:
    data = b''
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError('Connection closed')
        data += chunk
    return data


def _recv_tcp_packet(sock: socket.socket) -> bytes:
    length = struct.unpack('!I', _recv_exact_tcp(sock, 4))[0]
    return _recv_exact_tcp(sock, length)


def _send_tcp_packet(conn: socket.socket, data: bytes) -> None:
    conn.sendall(struct.pack('!I', len(data)) + data)


def _handle_tcp_client(conn: socket.socket, addr: tuple, tcp_sessions: TCPSessionRegistry,
                        vis) -> None:
    print(f"[relay] TCP client connected: {addr[0]}")
    client_id = None
    try:
        while True:
            data = _recv_tcp_packet(conn)
            try:
                payload = json.loads(data.decode('utf-8'))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue

            msg_client_id = payload.get('client_id', '')
            if client_id is None and msg_client_id:
                client_id = msg_client_id
                tcp_sessions.register(client_id, conn)

            if payload.get('type') == 'pin':
                vis.add_pin(payload.get('position', [0, 0, 0]), payload.get('label', ''))
                tcp_sessions.forward(client_id or '', data)
    except (ConnectionError, OSError):
        pass
    finally:
        if client_id:
            tcp_sessions.unregister(client_id)
        conn.close()
        print(f"[relay] TCP client disconnected: {addr[0]}")


def _start_tcp_listener(tcp_sessions: TCPSessionRegistry, vis) -> None:
    tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp_sock.bind(('', TCP_EVENT_PORT))
    tcp_sock.listen(10)
    print(f"[relay] TCP event listener on :{TCP_EVENT_PORT}")
    while True:
        conn, addr = tcp_sock.accept()
        threading.Thread(
            target=_handle_tcp_client,
            args=(conn, addr, tcp_sessions, vis),
            daemon=True
        ).start()


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
    tcp_sessions = TCPSessionRegistry()
    vis = Visualizer()
    packet_count = 0

    threading.Thread(target=_start_tcp_listener, args=(tcp_sessions, vis), daemon=True).start()
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

#!/usr/bin/env python3
"""
receive_scan.py — Receives scan data from WallHax iPhone app

Run this on your Mac BEFORE pressing "Send to Mac" on the phone.
Files are saved to ./scans/<session_name>/

Usage:
    python receive_scan.py
"""

import socket
import struct
import os
import sys

PORT = 9877
OUTPUT_DIR = "data"


def recv_exact(sock, n):
    """Receive exactly n bytes."""
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("Connection closed")
        data += chunk
    return data


def recv_packet(sock):
    """Receive a length-prefixed packet."""
    length_data = recv_exact(sock, 4)
    length = struct.unpack("!I", length_data)[0]
    return recv_exact(sock, length)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", PORT))
    server.listen(1)

    print(f"[receive_scan] Listening on port {PORT}...")
    print(f"[receive_scan] Press 'Send to Mac' on the iPhone.\n")

    while True:
        conn, addr = server.accept()
        print(f"[receive_scan] Connected from {addr[0]}")

        try:
            mission_id = recv_packet(conn).decode("utf-8")
            client_id = recv_packet(conn).decode("utf-8")
            print(f"[receive_scan] Mission: {mission_id[:8]}  Client: {client_id[:8]}")

            session_dir = os.path.join(OUTPUT_DIR, mission_id, client_id)
            os.makedirs(session_dir, exist_ok=True)

            # Receive file count
            file_count = int(recv_packet(conn).decode("utf-8"))
            print(f"[receive_scan] Expecting {file_count} files...\n")

            for i in range(file_count):
                # Receive relative path
                rel_path = recv_packet(conn).decode("utf-8")
                
                # Safety: strip any leading slashes or /private prefix
                rel_path = rel_path.lstrip("/")
                if rel_path.startswith("private"):
                    # Extract just the filename or last meaningful path
                    rel_path = os.path.basename(rel_path)

                # Receive file data
                file_data = recv_packet(conn)

                # Save file
                file_path = os.path.join(session_dir, rel_path)
                os.makedirs(os.path.dirname(file_path) or session_dir, exist_ok=True)

                with open(file_path, "wb") as f:
                    f.write(file_data)

                size_kb = len(file_data) / 1024
                print(f"  [{i+1}/{file_count}] {rel_path} ({size_kb:.0f} KB)")

            print(f"\n[receive_scan] Done! {file_count} files saved to: {session_dir}/")
            print(f"[receive_scan] Ready for another scan...\n")

        except Exception as e:
            print(f"[receive_scan] Error: {e}")
        finally:
            conn.close()


if __name__ == "__main__":
    main()
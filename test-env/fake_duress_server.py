import argparse
import json
import os
import socket
import threading
from datetime import datetime


class ClientState:
    def __init__(self, sock, addr):
        self.sock = sock
        self.addr = addr
        self.name = None
        self.buffer = ""


class RotatingAuditLogger:
    def __init__(self, log_path, max_bytes=10 * 1024 * 1024, backup_count=5):
        self.log_path = log_path
        self.max_bytes = max_bytes
        self.backup_count = backup_count
        self.lock = threading.Lock()

    def _ensure_parent(self):
        os.makedirs(os.path.dirname(self.log_path), exist_ok=True)

    def _rotate_if_needed(self, incoming_size):
        if self.max_bytes <= 0:
            return

        current_size = os.path.getsize(self.log_path) if os.path.exists(self.log_path) else 0
        if current_size + incoming_size <= self.max_bytes:
            return

        if self.backup_count > 0:
            oldest = f"{self.log_path}.{self.backup_count}"
            if os.path.exists(oldest):
                os.remove(oldest)

            for index in range(self.backup_count - 1, 0, -1):
                source = f"{self.log_path}.{index}"
                target = f"{self.log_path}.{index + 1}"
                if os.path.exists(source):
                    os.replace(source, target)

            if os.path.exists(self.log_path):
                os.replace(self.log_path, f"{self.log_path}.1")
        elif os.path.exists(self.log_path):
            os.remove(self.log_path)

    def _encode_entry(self, entry):
        return (json.dumps(entry, ensure_ascii=True) + "\n").encode("utf-8")

    def _fit_entry(self, entry):
        encoded = self._encode_entry(entry)
        if self.max_bytes <= 0 or len(encoded) <= self.max_bytes:
            return encoded

        compact_entry = {
            "timestamp": entry["timestamp"],
            "event": "log_entry_truncated",
            "original_event": entry.get("event"),
            "note": "entry exceeded max_bytes and was compacted",
        }
        compact_encoded = self._encode_entry(compact_entry)
        if len(compact_encoded) <= self.max_bytes:
            return compact_encoded

        # If the configured size is extremely small, fall back to a fixed-width line.
        fallback = (
            '{"event":"log_entry_truncated","note":"max_bytes too small"}\n'
        ).encode("utf-8")
        return fallback[: self.max_bytes]

    def write(self, event_type, **fields):
        entry = {
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "event": event_type,
            **fields,
        }
        encoded = self._fit_entry(entry)
        line = encoded.decode("utf-8", errors="ignore").rstrip("\n")
        print(line, flush=True)

        with self.lock:
            self._ensure_parent()
            self._rotate_if_needed(len(encoded))
            with open(self.log_path, "ab") as fh:
                fh.write(encoded)


class DuressServer:
    def __init__(self, host, port, logger):
        self.host = host
        self.port = port
        self.logger = logger
        self.clients = []
        self.lock = threading.Lock()

    def log_event(self, event_type, **fields):
        self.logger.write(event_type, **fields)

    def add_client(self, state):
        with self.lock:
            self.clients.append(state)

    def remove_client(self, state):
        with self.lock:
            if state in self.clients:
                self.clients.remove(state)
        try:
            state.sock.close()
        except OSError:
            pass

    def broadcast(self, payload, sender=None):
        data = payload.encode("ascii", errors="ignore")
        dead = []
        with self.lock:
            targets = list(self.clients)
        for state in targets:
            if sender is not None and state is sender:
                continue
            try:
                state.sock.sendall(data)
            except OSError:
                dead.append(state)
        for state in dead:
            self.remove_client(state)

    def handle_client(self, state):
        self.add_client(state)
        self.log_event(
            "client_connected",
            remote_ip=state.addr[0],
            remote_port=state.addr[1],
        )
        try:
            while True:
                chunk = state.sock.recv(512)
                if not chunk:
                    break
                text = chunk.decode("ascii", errors="ignore")
                state.buffer += text

                if state.name is None:
                    if "%" in state.buffer and "$" in state.buffer:
                        payload = state.buffer.strip()
                        self.log_event(
                            "injector_message",
                            remote_ip=state.addr[0],
                            remote_port=state.addr[1],
                            payload=payload,
                        )
                        self.broadcast(payload, sender=state)
                        state.buffer = ""
                        continue

                    if "\n" in state.buffer:
                        first, remainder = state.buffer.split("\n", 1)
                        state.name = first.strip()
                        state.buffer = remainder
                        self.log_event(
                            "client_registered",
                            remote_ip=state.addr[0],
                            remote_port=state.addr[1],
                            client_name=state.name,
                        )

                if state.name is not None and state.buffer:
                    payload = state.buffer.strip()
                    if payload:
                        self.log_event(
                            "client_message",
                            remote_ip=state.addr[0],
                            remote_port=state.addr[1],
                            client_name=state.name,
                            payload=payload,
                        )
                        self.broadcast(payload, sender=state)
                    state.buffer = ""
        finally:
            self.log_event(
                "client_disconnected",
                remote_ip=state.addr[0],
                remote_port=state.addr[1],
                client_name=state.name or "unregistered",
            )
            self.remove_client(state)

    def serve(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.port))
        server.listen(20)
        self.log_event(
            "server_listening",
            host=self.host,
            port=self.port,
            log_path=self.logger.log_path,
            max_bytes=self.logger.max_bytes,
            backup_count=self.logger.backup_count,
        )
        try:
            while True:
                sock, addr = server.accept()
                state = ClientState(sock, addr)
                threading.Thread(target=self.handle_client, args=(state,), daemon=True).start()
        finally:
            server.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8001)
    parser.add_argument("--log", required=True)
    parser.add_argument("--max-bytes", type=int, default=10 * 1024 * 1024)
    parser.add_argument("--backup-count", type=int, default=5)
    args = parser.parse_args()

    logger = RotatingAuditLogger(
        log_path=args.log,
        max_bytes=args.max_bytes,
        backup_count=args.backup_count,
    )
    DuressServer(args.host, args.port, logger).serve()


if __name__ == "__main__":
    main()

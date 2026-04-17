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
        self.registration = ""
        self.display_name = ""
        self.buffer = ""


class Logger:
    def __init__(self, log_path):
        self.log_path = log_path
        self.lock = threading.Lock()

    def write(self, event_type, **fields):
        entry = {
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "event": event_type,
            **fields,
        }
        line = json.dumps(entry, ensure_ascii=True)
        print(line, flush=True)
        with self.lock:
            os.makedirs(os.path.dirname(self.log_path), exist_ok=True)
            with open(self.log_path, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")


class LegacyWireServer:
    def __init__(self, host, port, logger):
        self.host = host
        self.port = port
        self.logger = logger
        self.clients = []
        self.lock = threading.Lock()

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

    def broadcast(self, payload, sender):
        rewritten = self.rewrite_sender(payload, sender.display_name)
        data = rewritten.encode("ascii", errors="ignore")
        dead = []
        with self.lock:
            targets = list(self.clients)

        for state in targets:
            if state is sender:
                continue
            try:
                state.sock.sendall(data)
            except OSError:
                dead.append(state)

        for state in dead:
            self.remove_client(state)

    def rewrite_sender(self, payload, sender_name):
        percent_index = payload.find("%")
        if percent_index <= 0:
            return payload
        return sender_name + payload[percent_index:]

    def handle_client(self, state):
        self.add_client(state)
        self.logger.write(
            "client_connected",
            remote_ip=state.addr[0],
            remote_port=state.addr[1],
        )
        try:
            while True:
                chunk = state.sock.recv(512)
                if not chunk:
                    break

                state.buffer += chunk.decode("ascii", errors="ignore")

                if not state.registration and "\n" in state.buffer:
                    first, remainder = state.buffer.split("\n", 1)
                    state.registration = first.strip()
                    state.display_name = state.registration
                    state.buffer = remainder
                    self.logger.write(
                        "client_registered",
                        remote_ip=state.addr[0],
                        remote_port=state.addr[1],
                        registration=state.registration,
                    )

                if state.registration and state.buffer.strip():
                    payload = state.buffer.strip()
                    self.logger.write(
                        "client_message",
                        remote_ip=state.addr[0],
                        remote_port=state.addr[1],
                        registration=state.registration,
                        payload=payload,
                    )
                    self.broadcast(payload, state)
                    state.buffer = ""
        finally:
            self.logger.write(
                "client_disconnected",
                remote_ip=state.addr[0],
                remote_port=state.addr[1],
                registration=state.registration or "unregistered",
            )
            self.remove_client(state)

    def serve(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.port))
        server.listen(20)
        self.logger.write("server_listening", host=self.host, port=self.port, log_path=self.logger.log_path)
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
    parser.add_argument("--port", type=int, default=8011)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    logger = Logger(args.log)
    LegacyWireServer(args.host, args.port, logger).serve()


if __name__ == "__main__":
    main()

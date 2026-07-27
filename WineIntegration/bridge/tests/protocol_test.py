#!/usr/bin/env python3

import os
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

MAGIC = 0x31494742
VERSION = 5
HEADER = struct.Struct("<IHHIIII")

HELLO = 1
AUTHENTICATE = 2
DISCOVER_TARGET = 3
PING = 5
QUERY_FOREGROUND = 6
SET_FOREGROUND = 7
PREPARE_TARGET_INPUT = 8
PRIME_TARGET_INPUT = 9
QUERY_KEY_STATE = 40
RELEASE_ALL = 50
SHUTDOWN = 51
CONFIGURE_INPUT_CONTEXT = 52

OK = 0
AUTHENTICATION_REQUIRED = 4
AUTHENTICATION_FAILED = 5
TARGET_REQUIRED = 8
TARGET_NOT_FOUND = 9


def free_port() -> int:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    listener.close()
    return port


def receive_exact(client: socket.socket, length: int) -> bytes:
    data = bytearray()
    while len(data) < length:
        chunk = client.recv(length - len(data))
        if not chunk:
            raise RuntimeError("bridge closed the connection")
        data.extend(chunk)
    return bytes(data)


class Client:
    def __init__(self, port: int):
        deadline = time.monotonic() + 20
        error = None
        while time.monotonic() < deadline:
            try:
                self.socket = socket.create_connection(("127.0.0.1", port), 0.5)
                break
            except OSError as current:
                error = current
                time.sleep(0.05)
        else:
            raise RuntimeError(f"unable to connect to bridge: {error}")
        self.request_id = 1

    def request(self, command: int, payload: bytes = b"") -> tuple[int, bytes]:
        request_id = self.request_id
        self.request_id += 1
        self.socket.sendall(
            HEADER.pack(MAGIC, VERSION, command, request_id, len(payload), 0, 0)
            + payload
        )
        response = HEADER.unpack(receive_exact(self.socket, HEADER.size))
        magic, version, response_command, response_id, length, status, reserved = response
        assert magic == MAGIC
        assert version == VERSION
        assert response_command == command
        assert response_id == request_id
        assert reserved == 0
        return status, receive_exact(self.socket, length)

    def close(self) -> None:
        self.socket.close()


def launch(wine: Path, prefix: Path, bridge: Path, port: int, token: str):
    environment = os.environ.copy()
    environment["WINEPREFIX"] = str(prefix)
    environment["WINEDEBUG"] = "-all"
    environment["BETTERGI_WINE_BRIDGE_TOKEN"] = token
    return subprocess.Popen(
        [str(wine), str(bridge), "--port", str(port)],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def wait_for_exit(process: subprocess.Popen, timeout: float = 10) -> None:
    try:
        status = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=5)
        raise AssertionError("bridge did not exit after its client disconnected")
    assert status == 0


def run_protocol_test(wine: Path, prefix: Path, bridge: Path) -> None:
    port = free_port()
    token = "0123456789abcdef" * 4
    process = launch(wine, prefix, bridge, port, token)
    client = Client(port)

    status, hello = client.request(HELLO)
    assert status == OK
    assert len(hello) == 16

    status, _ = client.request(PING)
    assert status == AUTHENTICATION_REQUIRED

    status, _ = client.request(AUTHENTICATE, b"x" * len(token))
    assert status == AUTHENTICATION_FAILED

    status, _ = client.request(AUTHENTICATE, token.encode())
    assert status == OK

    second = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    second.settimeout(1)
    assert second.connect_ex(("127.0.0.1", port)) != 0
    second.close()

    status, _ = client.request(DISCOVER_TARGET, b"DefinitelyMissing.exe")
    assert status == TARGET_NOT_FOUND

    status, _ = client.request(QUERY_KEY_STATE, struct.pack("<HH", 0x46, 0))
    assert status == TARGET_REQUIRED
    status, _ = client.request(QUERY_FOREGROUND, struct.pack("<HH", 0x46, 0))
    assert status == TARGET_REQUIRED
    status, _ = client.request(SET_FOREGROUND, struct.pack("<HH", 0x46, 0))
    assert status == TARGET_REQUIRED
    status, _ = client.request(PREPARE_TARGET_INPUT)
    assert status == TARGET_REQUIRED
    status, _ = client.request(PRIME_TARGET_INPUT)
    assert status == TARGET_REQUIRED
    status, _ = client.request(
        CONFIGURE_INPUT_CONTEXT,
        struct.pack("<BBH", 1, 1, 3000),
    )
    assert status == TARGET_REQUIRED

    status, _ = client.request(RELEASE_ALL)
    assert status == OK

    status, _ = client.request(SHUTDOWN)
    assert status == OK
    client.close()
    wait_for_exit(process)


def run_disconnect_test(wine: Path, prefix: Path, bridge: Path) -> None:
    port = free_port()
    token = "fedcba9876543210" * 4
    process = launch(wine, prefix, bridge, port, token)
    client = Client(port)
    assert client.request(AUTHENTICATE, token.encode())[0] == OK
    client.close()
    wait_for_exit(process)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: protocol_test.py <wine> <prefix> <bridge.exe>", file=sys.stderr)
        return 2
    wine = Path(sys.argv[1]).resolve()
    prefix = Path(sys.argv[2]).resolve()
    bridge = Path(sys.argv[3]).resolve()
    prefix.mkdir(parents=True, exist_ok=True)
    run_protocol_test(wine, prefix, bridge)
    run_disconnect_test(wine, prefix, bridge)
    print("BetterGI Wine bridge protocol test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

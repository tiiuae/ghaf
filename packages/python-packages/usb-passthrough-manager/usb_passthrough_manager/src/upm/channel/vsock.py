# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import logging
import socket
import threading
import time
from collections.abc import Callable
from typing import Any

import upm.channel.json_transport as json_transport
from upm.logger import log_entry_exit

logger = logging.getLogger("upm")

AF_VSOCK = getattr(socket, "AF_VSOCK", None)
SOCK_STREAM = socket.SOCK_STREAM


class VsockServer(threading.Thread):
    """Guest VM Server: listens for a vsock connection, receives messages."""

    def __init__(
        self,
        on_message: Callable[[dict[str, Any]], None],
        on_connect: Callable[[], None],
        on_disconnect: Callable[[], None],
        cid: int,
        port: int,
    ):
        super().__init__(daemon=True)
        self.on_message = on_message
        self.on_connect = on_connect
        self.on_disconnect = on_disconnect
        self.conn = None
        self.stop_flag = threading.Event()
        self.lock = threading.Lock()
        self.cid = cid
        self.port = port
        try:
            self.sock = socket.socket(AF_VSOCK, SOCK_STREAM)
            self.sock.bind((cid, port))
            self.sock.listen(1)
            logger.info("Socket successfully created")
        except OSError as err:
            raise SystemError(f"VSOCK server setup failed: {err}") from err

    def __del__(self):
        self.stop()

    @log_entry_exit
    def client(self):
        if self.conn is not None:
            return self.conn
        new_connection = False
        with self.lock:
            if self.conn is None:
                self.conn, _ = self.sock.accept()
                new_connection = True
        if new_connection:
            self.on_connect()
        return self.conn

    @log_entry_exit
    def close_connection(self):
        with self.lock:
            if self.conn is not None:
                self.conn.close()
                self.conn = None
                self.on_disconnect()

    @log_entry_exit
    def run(self):
        while not self.stop_flag.is_set():
            try:
                for msg in json_transport.receive(self.client()):
                    self.on_message(msg)
            except OSError as err:
                logger.error(f"VSOCK server error: {err}")
            self.close_connection()

    @log_entry_exit
    def send(self, data: dict[str, Any]) -> bool:
        logger.debug(f"Sending {data}")
        for _ in range(5):
            try:
                json_transport.send(self.client(), data)
                return True
            except Exception:
                logger.error("Vsock server error, send failed! Retrying...")
                self.close_connection()
                continue
        return False

    @log_entry_exit
    def stop(self):
        self.stop_flag.set()
        time.sleep(1)
        try:
            self.close_connection()
        except Exception:
            pass
        try:
            if self.sock:
                self.sock.close()
        except Exception:
            pass


class VsockClient(threading.Thread):
    """Host Client: send/receive message to server."""

    def __init__(
        self,
        on_message: Callable[[dict[str, Any]], None],
        on_connect: Callable[[], None],
        on_disconnect: Callable[[], None],
        cid: int,
        port: int,
    ):
        super().__init__(daemon=True)
        self.on_message = on_message
        self.on_connect = on_connect
        self.on_disconnect = on_disconnect
        self.conn = None
        self.stop_flag = threading.Event()
        self.lock = threading.Lock()
        self.port = port
        self.cid = cid

    @log_entry_exit
    def server(self) -> socket.socket:
        with self.lock:
            if self.conn is None:
                self.conn = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
                while True:
                    try:
                        # Wait for server,
                        # TODO: better to start as socket unit
                        logger.debug(
                            f"Waiting for server. cid:{self.cid}, port:{self.port}"
                        )
                        self.conn.connect((self.cid, self.port))
                        break
                    except OSError:
                        time.sleep(1)
            return self.conn

    @log_entry_exit
    def close_connection(self):
        with self.lock:
            if self.conn is not None:
                self.conn.close()
                self.conn = None
                self.on_disconnect()

    @log_entry_exit
    def run(self):
        while not self.stop_flag.is_set():
            try:
                for msg in json_transport.receive(self.server()):
                    self.on_message(msg)
            except OSError as err:
                logger.error(f"VSOCK server error: {err}")
            self.close_connection()

    @log_entry_exit
    def send(self, data: dict[str, Any]) -> bool:
        for _ in range(5):
            try:
                json_transport.send(self.server(), data)
                return True
            except Exception:
                logger.error("Vsock server error, send failed! Retrying...")
                self.close_connection()
                continue
        return False

    @log_entry_exit
    def stop(self):
        self.stop_flag.set()
        time.sleep(1)
        try:
            self.close_connection()
        except Exception:
            pass

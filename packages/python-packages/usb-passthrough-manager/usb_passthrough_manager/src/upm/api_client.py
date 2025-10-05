# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import socket
import json
import threading
import time

from upm.logger import logger


class APIClient:
    def __init__(self, port=2000, cid=2):
        self.port = port
        self.cid = cid
        self.sock = None

    def connect(self):
        logger.info("Connecting to vsock cid %s on port %s", self.cid, self.port)
        self.sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        self.sock.connect((self.cid, self.port))
        logger.info("Connected")

    def send(self, msg):
        data = json.dumps(msg) + "\n"
        self.sock.sendall(data.encode("utf-8"))
        return self.recv()

    def recv(self):
        buffer = ""
        while True:
            data = self.sock.recv(4096)
            if not data:
                logger.info("API connection closed by remote")
                break
            buffer += data.decode("utf-8")
            while "\n" in buffer:
                msg, buffer = buffer.split("\n", 1)
                try:
                    return json.loads(msg)
                except ValueError:
                    logger.error("Invalid JSON in API response: %s", msg)
        return None

    def close(self):
        if self.sock:
            self.sock.close()

    def enable_notifications(self):
        response = self.send({"action": "enable_notifications"})
        if response.get("result") != "ok":
            logger.error("Failed to enable notifications: %s", response)

    def usb_list(self):
        return self.send({"action": "usb_list"})

    def usb_attach(self, device_node, vm):
        return self.send({"action": "usb_attach", "device_node": device_node, "vm": vm})

    def usb_detach(self, device_node):
        return self.send({"action": "usb_detach", "device_node": device_node})

    # pylint: disable=too-many-positional-arguments
    @classmethod
    def recv_notifications(cls, callback, port=2000, cid=2, reconnect_delay=3):
        client = cls(port=port, cid=cid)

        def _listener():
            while True:
                try:
                    client.connect()
                    client.enable_notifications()

                    buffer = ""
                    while True:
                        data = client.sock.recv(4096)
                        if not data:
                            raise ConnectionError(
                                "API connection for notifications closed by remote"
                            )
                        buffer += data.decode("utf-8")
                        while "\n" in buffer:
                            msg, buffer = buffer.split("\n", 1)
                            try:
                                parsed = json.loads(msg)
                                callback(parsed)
                            except ValueError:
                                logger.error(
                                    "Invalid JSON in API notification: %s", msg
                                )
                except OSError as e:
                    logger.warning("Notification listener error: %s", e)
                    logger.warning("Reconnecting in %s sec...", reconnect_delay)
                finally:
                    client.close()
                    time.sleep(reconnect_delay)

        thread = threading.Thread(target=_listener, daemon=True)
        thread.start()
        return thread, client

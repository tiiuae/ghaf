# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import json
import logging
import os
import stat
import tempfile
from pathlib import Path
from typing import Any

from upm.channel.vsock import VsockServer
from upm.guest.popup_qt5 import show_new_device_popup_async
from upm.logger import log_entry_exit

logger = logging.getLogger("upm")


class DeviceRegister:
    def __init__(self, cid: int, port: int, data_dir: str):
        self.server = VsockServer(
            on_message=self.on_msg,
            on_connect=self.on_connect,
            on_disconnect=self.on_disconnect,
            cid=cid,
            port=port,
        )

        self.connected = False
        self.device_registry = {}
        self.regpath = Path(data_dir)
        self.regpath.mkdir(parents=True, exist_ok=True)
        try:
            # Ensure directory is accessible by other users to read the registry file.
            os.chmod(self.regpath, 0o755)
        except OSError as e:
            logger.error(
                f"Failed to set permissions on registry directory {self.regpath}: {e}"
            )

        self.regFile = self.regpath / "usb_db.json"
        if not self.regFile.exists():
            self.regFile.write_text("{}", encoding="utf-8")

        # Set permissions to be readable by all users.
        # This service runs as root, so we need to explicitly set permissions.
        try:
            os.chmod(self.regFile, 0o644)
        except OSError as e:
            logger.error(
                f"Failed to set permissions on registry file {self.regFile}: {e}"
            )

    def __del__(self):
        self.stop()
        if self.regFile.exists():
            os.remove(self.regFile)

    @log_entry_exit
    def start(self):
        logger.debug("")
        self.server.start()

    @log_entry_exit
    def stop(self):
        self.server.stop()

    @log_entry_exit
    def wait(self):
        self.server.join()

    @log_entry_exit
    def request_passthrough(self, device_id: str, new_vm: str) -> bool:
        device_schema = {
            "type": "passthrough_request",
            "device_id": device_id,
            "current-vm": new_vm,
        }
        if not self.server.send(device_schema):
            logger.error("Failed to send passthrough request to host")
            return False
        return True

    @log_entry_exit
    def on_connect(self):
        self.connected = True
        logger.info("Connected to Host, Requesting devices...")
        device_schema = {
            "type": "get_devices",
        }
        if not self.server.send(device_schema):
            logger.critical("System error! Service restart required.")

    @log_entry_exit
    def on_disconnect(self):
        if self.connected:
            logger.info("Host Disconnected;")
        self.connected = False

    @log_entry_exit
    def atomic_write_registry(self, data: dict[str, Any]) -> None:
        try:
            # Atomic write: write to tmp then replace
            with tempfile.NamedTemporaryFile(
                "w", delete=False, dir=self.regpath, encoding="utf-8"
            ) as tf:
                json.dump(data, tf, indent=2, ensure_ascii=False)
                tmp_name = tf.name
                os.fchmod(
                    tf.fileno(),
                    stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH,
                )  # 0644
            os.replace(tmp_name, self.regFile)  # atomic on POSIX
        except Exception as e:
            logger.error(f"Failed to write registry: {e}")
        finally:
            if tmp_name and os.path.exists(tmp_name):
                try:
                    os.unlink(tmp_name)
                except OSError as e:
                    logger.error(f"Failed to clean up temporary file: {tmp_name}: {e}")

    @log_entry_exit
    def passthrough_request(self, device_id: str, new_vm: str) -> bool:
        device_schema = {
            "type": "passthrough_request",
            "device_id": device_id,
            "current-vm": new_vm,
        }
        if not self.server.send(device_schema):
            logger.critical("Passthrough error! Send request failed.")
            return False
        return True

    @log_entry_exit
    def on_msg(self, msg: dict[str, Any]):
        msgtype = msg.get("type")
        # A new device connected
        if msgtype == "device_connected":
            device = msg.get("device") or {}
            device_id = device.get("device_id")
            if not device_id:
                logger.error("Device_connected: missing device_id")
                return

            entry = {
                "vendor": device.get("vendor") or "",
                "product": device.get("product") or "",
                "permitted-vms": list(device.get("permitted-vms") or []),
                "current-vm": device.get("current-vm") or "",
            }

            self.device_registry[device_id] = entry
            self.atomic_write_registry(self.device_registry)
            logger.info(f"device_connected: {device_id} -> {entry['current-vm']}")
            show_new_device_popup_async(
                passthrough_handler=self.passthrough_request,
                device_id=device_id,
                vendor=entry["vendor"],
                product=entry["product"],
                permitted_vms=entry["permitted-vms"],
                current_vm=entry["current-vm"],
            )
        # A device removed
        elif msgtype == "device_removed":
            device_id = msg.get("device_id")
            if device_id in self.device_registry:
                del self.device_registry[device_id]
                self.atomic_write_registry(self.device_registry)
                logger.info(f"device_removed: {device_id} removed")
            else:
                logger.error(f"{device_id} not found!")
        # A snapshot of connected devices
        elif msgtype == "connected_devices":
            devices = msg.get("devices")
            self.device_registry = devices
            self.atomic_write_registry(self.device_registry)
        # A device switched
        elif msgtype == "passthrough_ack":
            device_id = msg.get("device_id")
            new_vm = msg.get("current-vm")
            self.device_registry[device_id]["current-vm"] = new_vm
            self.atomic_write_registry(self.device_registry)
        elif msgtype == "reset":
            self.device_registry.clear()
            self.atomic_write_registry(self.device_registry)
        else:
            logger.error(f"unknown schema: {msg}")

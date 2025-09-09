# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import logging
import os
import threading
from pathlib import Path

from upm.guest.device_registry import DeviceRegister
from upm.logger import log_entry_exit

logger = logging.getLogger("upm")


def _create_fifo(service_dir: str) -> Path:
    fifo = Path(service_dir) / "app_request.fifo"
    try:
        if fifo.exists():
            os.unlink(fifo)
        os.mkfifo(fifo, 0o600)
        os.chmod(fifo, 0o622)  # write only for others
    except FileExistsError:
        raise RuntimeError("Can not create FIFO!")
    return fifo


def fifo_reader_thread(fifo: Path, svc: DeviceRegister, stop: threading.Event) -> None:
    while not stop.is_set():
        with open(fifo, encoding="utf-8") as f:
            logger.debug("Fifo opened")
            for line in f:
                logger.debug(f"Received request {line}")
                device_id, new_vm = line.rstrip("\n").split("->", 1)
                if not svc.request_passthrough(device_id, new_vm):
                    logger.error("Failed to send passthrough request")
                else:
                    logger.info(
                        f"Passthrough request sent successfully to host: {device_id} -> {new_vm}"
                    )


@log_entry_exit
def handle_app_request(
    service_dir: str, svc: DeviceRegister
) -> tuple[threading.Thread, threading.Event]:
    fifo = _create_fifo(service_dir)
    stop_event = threading.Event()
    th = threading.Thread(target=fifo_reader_thread, args=(fifo, svc, stop_event))
    th.start()
    return th, stop_event

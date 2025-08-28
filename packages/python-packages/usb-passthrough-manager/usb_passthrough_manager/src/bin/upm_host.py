# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import argparse
import json
import logging
import os
from pathlib import Path

from upm.host.service import HostService
from upm.logger import setup_logger

logger = logging.getLogger("upm")


def emulate(svc):
    logger.info("Emulating...")
    fifo = Path("/tmp/device_event.fifo")
    try:
        if fifo.exists():
            os.unlink(fifo)
        os.mkfifo(fifo, 0o622)  # write only for others
    except FileExistsError:
        raise RuntimeError("Can not create FIFO!")
    while True:
        with open(fifo, encoding="utf-8") as f:
            logger.debug("Fifo opened")
            for line in f:
                try:
                    s = line.lstrip("\ufeff").rstrip("\r\n")
                    logger.debug(f"Received request {line}")
                    request = json.loads(s)
                    logger.debug("Request loaded to JSON")
                except json.JSONDecodeError:
                    logger.error("JSON parse failed! Send new command!")
                    break
                if "type" not in request:
                    logger.error(
                        "Could not find type field in request! Send new command!"
                    )
                    break
                logger.debug("Processing request: " + request["type"])
                match request["type"]:
                    case "passthrough_request":
                        if "device_id" not in request or "current-vm" not in request:
                            logger.error(
                                "Could not find device_id or current-vm field in request! Send new command!"
                            )
                        else:
                            device_id = request.get("device_id")
                            target_vm = request.get("current-vm")
                            if not svc.notify_device_passthrough(device_id, target_vm):
                                logger.error("Notify error! Service restart required.")
                            else:
                                logger.info(
                                    f"Device {device_id} passed through to VM {target_vm}"
                                )
                        break
                    case "reset":
                        if not svc.reset():
                            logger.error("Couldn't send reset request.")
                        break
                    case "device_connected":
                        if "device" not in request:
                            logger.error(
                                "Could not find device field in request! Send new command!"
                            )
                        elif (
                            "device_id" not in request["device"]
                            or "vendor" not in request["device"]
                            or "product" not in request["device"]
                            or "permitted-vms" not in request["device"]
                            or "current-vm" not in request["device"]
                        ):
                            logger.error(
                                "Could not find connected device data in request! Send new command!"
                            )
                        else:
                            device_id = request["device"].get("device_id")
                            vendor = request["device"].get("vendor")
                            product = request["device"].get("product")
                            permitted_vms = request["device"].get("permitted-vms")
                            current_vm = request["device"].get("current-vm")

                            logger.debug("device_connected request.")
                            if not svc.notify_device_connected(
                                device_id, vendor, product, permitted_vms, current_vm
                            ):
                                logger.error("Notify device connected failed")
                            else:
                                logger.info(f"Device {device_id} connected")
                        break
                    case "device_removed":
                        if "device_id" not in request:
                            logger.error(
                                "Could not find device_id field in request! Send new command!"
                            )
                        else:
                            device_id = request.get("device_id")
                            if not svc.notify_device_disconnected(device_id):
                                logger.error("Notify device disconnected failed")
                            else:
                                logger.info(f"Device {device_id} disconnected")
                        break
                    case _:
                        logger.error("Unknown request type!")


def build_parser():
    p = argparse.ArgumentParser(description="Host ↔ Conroller VM")
    p.add_argument("--cid", type=int, default=5, help="GUI VM vsock CID (default: 5)")
    p.add_argument(
        "--port",
        type=int,
        default=7000,
        help="GUI VM vsock port for usb passthrough manager service (default 7000)",
    )
    p.add_argument("--loglevel", type=str, default="info", help="Log level")
    p.add_argument("--emulate", type=bool, default=False, help="Emulate mode(test)")
    return p


def fake_device_passthrough(metadata, device_id, new_vm):
    logger.info(
        f"device id: {device_id} connected to vm: {new_vm}, metadata: {metadata}"
    )
    return True


def main():
    args = build_parser().parse_args()
    setup_logger(args.loglevel)

    svc = HostService(
        port=args.port,
        cid=args.cid,
        passthrough_handler=fake_device_passthrough,
        metadata="fake_passthrough_device_metadata",
    )
    svc.start()
    logger.info("[HOST] Running. Ctrl+C to exit.")
    if args.emulate:
        logger.info("Running in emulator mode")
        emulate(svc)

    try:
        svc.wait()
    except KeyboardInterrupt:
        pass
    finally:
        svc.stop()


if __name__ == "__main__":
    main()

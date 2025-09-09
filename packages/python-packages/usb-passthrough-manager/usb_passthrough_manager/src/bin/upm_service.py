# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import argparse
import logging

from upm.guest.app_interface import handle_app_request
from upm.guest.device_registry import DeviceRegister
from upm.logger import setup_logger

logger = logging.getLogger("upm")


def build_parser():
    p = argparse.ArgumentParser(description="controller VM ↔ HOST (vsock)")
    p.add_argument(
        "--cid", type=int, default=5, help="Host vsock listen port (default 5)"
    )
    p.add_argument(
        "--port", type=int, default=7000, help="Host vsock listen port (default 7000)"
    )
    p.add_argument(
        "--dir",
        type=str,
        default="/tmp/usb-passthrough/",
        help="Directory to store registry",
    )
    p.add_argument("--loglevel", type=str, default="info", help="Log level")
    return p


def main():
    args = build_parser().parse_args()
    setup_logger(args.loglevel)

    svc = DeviceRegister(args.cid, args.port, args.dir)
    svc.start()
    th, stop_th = handle_app_request(args.dir, svc)
    try:
        svc.wait()
    except KeyboardInterrupt:
        pass
    finally:
        svc.stop()
        stop_th.set()
        th.join()


if __name__ == "__main__":
    main()

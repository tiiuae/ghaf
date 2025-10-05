# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import argparse
import logging

from upm.win import USBDeviceNotification
from upm.logger import setup_logger

logger = logging.getLogger("upm")


def build_parser():
    p = argparse.ArgumentParser(description="controller VM ↔ HOST (vsock)")
    p.add_argument(
        "--port", type=int, default=2000, help="Host vsock listen port (default 7000)"
    )
    p.add_argument("--loglevel", type=str, default="info", help="Log level")
    return p


def main():
    args = build_parser().parse_args()
    setup_logger(args.loglevel)

    USBDeviceNotification(args.port)


if __name__ == "__main__":
    main()

# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import argparse
import logging
import sys

from upm.win import USBDeviceMap
from upm.logger import setup_logger

logger = logging.getLogger("upm")


def build_parser():
    p = argparse.ArgumentParser(description="Guest USB controller")
    p.add_argument("--port", type=int, default=2000, help="vsock server port")
    p.add_argument("--loglevel", type=str, default="info", help="Log level")
    return p


def main():
    args = build_parser().parse_args()
    setup_logger(args.loglevel)
    app = USBDeviceMap(args.port)
    sys.exit(app.run(None))


if __name__ == "__main__":
    main()

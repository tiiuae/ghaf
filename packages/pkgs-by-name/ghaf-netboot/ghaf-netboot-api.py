#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# The shebang is load-bearing: patchShebangs has nothing to rewrite without it,
# and the file then gets executed as a shell script, which "runs" this docstring
# as commands and fails in a thoroughly confusing way.
"""HTTP side of ghaf-netboot: the Pixiecore boot API plus the static files.

Pixiecore in `api` mode asks us what to do with every machine that tries to PXE
boot, by GETting /v1/boot/<mac>. Answering 404 tells it to ignore that machine.
That is the whole reason this exists rather than `pixiecore boot`: on a shared
lab LAN we must serve exactly the machines we were pointed at and nothing else.
An unattended install is destructive, so "boots whatever asks" is not an option.

Also serves the netboot artefacts and the image directory, so there is one
process and one port for everything on the HTTP side.

  /v1/boot/<mac>          boot instructions, or 404 for machines not allowlisted
  /boot/bzImage,/initrd   the netboot kernel and initrd
  /ghaf-image/...         ghaf-image.raw.zst and ghaf-image.bmap

Threaded because the image is multi-GB: a single-threaded server would block
every API call for the duration of one machine's download.
"""

import argparse
import http.server
import json
import os
import re
import socketserver
import sys
import threading
from typing import ClassVar

MAC_RE = re.compile(r"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$")


def normalise_mac(value):
    """Accept the usual spellings and return aa:bb:cc:dd:ee:ff, or None."""
    cleaned = value.strip().lower().replace("-", ":")
    # Pixiecore percent-encodes nothing, but be forgiving about it anyway.
    cleaned = cleaned.replace("%3a", ":")
    if MAC_RE.match(cleaned):
        return cleaned
    return None


class Handler(http.server.SimpleHTTPRequestHandler):
    # Set by main(); class attributes so every thread sees the same values.
    allowed: ClassVar[frozenset] = frozenset()
    boot_json: ClassVar[dict] = {}
    exit_after_serve: ClassVar[bool] = False

    def log_message(self, fmt, *args):
        sys.stderr.write(f"ghaf-netboot: {self.address_string()} - {fmt % args}\n")

    def do_GET(self):
        if self.path.startswith("/v1/boot/"):
            return self.serve_boot_api(self.path[len("/v1/boot/") :])

        result = super().do_GET()

        # The image is the last and largest thing a client fetches, so a
        # completed transfer of it means this install has what it needs. Shut
        # down rather than sit on the LAN answering PXE for the rest of the day.
        if type(self).exit_after_serve and self.path.endswith(".raw.zst"):
            self.log_message("image served in full, shutting down")
            # shutdown() blocks until serve_forever() returns, so it can never
            # be called from a request thread -- hence the extra thread.
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        return result

    def serve_boot_api(self, raw_mac):
        mac = normalise_mac(raw_mac)
        if mac is None:
            self.send_error(400, "malformed MAC")
            return
        if mac not in type(self).allowed:
            # 404 is Pixiecore's "ignore this machine". This is the allowlist.
            self.log_message("ignoring %s (not in allowlist)", mac)
            self.send_error(404, "not allowlisted")
            return

        body = json.dumps(type(self).boot_json).encode()
        self.log_message("booting %s", mac)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="directory to serve")
    ap.add_argument("--listen", required=True, help="address to bind")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument(
        "--mac",
        action="append",
        default=[],
        help="allowlisted client MAC; repeatable. No MACs means no machine boots.",
    )
    ap.add_argument("--cmdline", required=True, help="kernel command line")
    ap.add_argument(
        "--exit-after-serve",
        action="store_true",
        help="stop once the image has been fetched in full",
    )
    args = ap.parse_args()
    Handler.exit_after_serve = args.exit_after_serve

    base = f"http://{args.listen}:{args.port}"
    Handler.boot_json = {
        "kernel": f"{base}/boot/bzImage",
        "initrd": [f"{base}/boot/initrd"],
        "cmdline": args.cmdline,
        "message": "Ghaf netboot installer",
    }

    macs = set()
    for raw in args.mac:
        mac = normalise_mac(raw)
        if mac is None:
            sys.exit(f"ghaf-netboot: not a MAC address: {raw}")
        macs.add(mac)
    Handler.allowed = frozenset(macs)
    if not macs:
        # Fail closed. An empty allowlist that silently served everyone would be
        # the exact failure this component exists to prevent.
        sys.exit("ghaf-netboot: refusing to start with an empty MAC allowlist")

    os.chdir(args.root)
    with Server((args.listen, args.port), Handler) as httpd:
        print(
            f"ghaf-netboot: HTTP on {base}, serving {args.root}, "
            f"allowlist: {' '.join(sorted(macs))}",
            file=sys.stderr,
            flush=True,
        )
        httpd.serve_forever()


if __name__ == "__main__":
    main()

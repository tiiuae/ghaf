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

TWO TIERS, AND WHY
------------------
A hundred machines pull ~685 MB of kernel+initrd and then ~10.5 GB of image
each: roughly 1 TB, which is about two and a half hours on 1 GbE no matter what
this file does. What this file decides is whether those hours produce a hundred
installs or a hundred timeouts.

  tier 1  /v1/boot, bzImage, initrd, .bmap   served greedily, never queued
          The client is still in FIRMWARE here. iPXE's embedded boot.ipxe gets
          ten DHCP attempts and then reboots, so a client made to wait at this
          stage falls out of the PXE path altogether. ~68 GB fleet-wide.

  tier 2  ghaf-image.raw.zst                 admission-controlled
          The client is now running Linux with curl and no firmware timer, so it
          can afford to wait. Eight clients at ~15 MB/s each finish in ~12 min
          and the next batch starts; a hundred sharing the same pipe each crawl
          at ~1.2 MB/s and time out instead. Same total bytes, very different
          number of successful installs.

Clients over the cap get 503 + Retry-After rather than a held connection, so the
queue lives in the clients (which are already retrying) instead of in server
memory. ghaf-installer's wait_for_image_slot() is the other half of that
contract -- it probes with a one-byte range request before streaming.
"""

import argparse
import http.server
import io
import json
import os
import re
import socket
import socketserver
import sys
import threading
import time
from typing import ClassVar

MAC_RE = re.compile(r"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$")

# Anything ending in this is tier 2. The bmap deliberately is not: it is ~50 KB
# and the client needs it before it can ask for a slot at all.
IMAGE_SUFFIX = ".raw.zst"


def normalise_mac(value):
    """Accept the usual spellings and return aa:bb:cc:dd:ee:ff, or None."""
    cleaned = value.strip().lower().replace("-", ":")
    # Pixiecore percent-encodes nothing, but be forgiving about it anyway.
    cleaned = cleaned.replace("%3a", ":")
    if MAC_RE.match(cleaned):
        return cleaned
    return None


class Fleet:
    """Per-client progress, so a multi-hour run is legible from the console.

    At one client the request log was the status display. At a hundred it is
    unreadable, and the only question an operator actually has -- "is it moving
    or is it stuck?" -- cannot be answered from it at all.
    """

    # No kernel/initrd stages. Pixiecore fetches those from us and streams them
    # to the machine itself, so they arrive from OUR address, not the target's:
    # there is no honest way to attribute them to a client at the HTTP layer, and
    # attributing them to the last MAC offered would be wrong the moment two
    # machines boot at once -- i.e. always, for a fleet.
    ORDER: ClassVar[list] = [
        "offered",
        "queued",
        "downloading",
        "complete",
    ]

    def __init__(self, roster=None):
        self._lock = threading.Lock()
        self._state = {}
        self._roster = frozenset(roster or ())
        self._announced_complete = False

    def mark(self, mac, state):
        """Record progress. Never moves a client backwards through ORDER."""
        if not mac:
            return
        with self._lock:
            current = self._state.get(mac)
            if current is not None and self.ORDER.index(state) <= self.ORDER.index(
                current
            ):
                return
            self._state[mac] = state

    def summary(self):
        with self._lock:
            counts = {s: 0 for s in self.ORDER}
            for state in self._state.values():
                counts[state] += 1
            total = len(self._state)
        parts = [f"{s}={counts[s]}" for s in self.ORDER if counts[s]]
        return f"{total} client(s): " + (", ".join(parts) if parts else "none yet")

    def roster_complete(self):
        """True once every rostered MAC has finished. False if there is no roster."""
        if not self._roster:
            return False
        with self._lock:
            if self._announced_complete:
                return False
            done = {m for m, s in self._state.items() if s == "complete"}
            if self._roster <= done:
                self._announced_complete = True
                return True
        return False

    def pending(self):
        with self._lock:
            done = {m for m, s in self._state.items() if s == "complete"}
        return sorted(self._roster - done)


class Handler(http.server.SimpleHTTPRequestHandler):
    # Set by main(); class attributes so every thread sees the same values.
    allowed: ClassVar[frozenset] = frozenset()
    any_mac: ClassVar[bool] = False
    boot_json: ClassVar[dict] = {}
    exit_after_serve: ClassVar[bool] = False
    image_slots: ClassVar[threading.BoundedSemaphore] = threading.BoundedSemaphore(8)
    max_images: ClassVar[int] = 8
    retry_after: ClassVar[int] = 30
    fleet: ClassVar[Fleet] = Fleet()

    def log_message(self, fmt, *args):
        sys.stderr.write(f"ghaf-netboot: {self.address_string()} - {fmt % args}\n")

    # --- helpers -------------------------------------------------------------

    def _client_mac(self):
        """MAC for the peer, from the kernel's neighbour table.

        Never used for authorisation -- that happens in serve_boot_api, on the
        MAC pixiecore tells us.

        ARP rather than a table built from the boot API, because the boot API's
        peer is PIXIECORE, not the machine: it proxies /v1/boot and the artefact
        fetches, so everything before the image arrives from our own address.
        Only the installer -- once it is running Linux on the target -- connects
        to us directly, and by then the machine is a neighbour, which PXE
        guarantees anyway since it cannot cross a router.
        """
        return arp_lookup(self.client_address[0])

    def _send_503(self, position):
        body = b"queued\n"
        self.send_response(503)
        self.send_header("Retry-After", str(type(self).retry_after))
        self.send_header("X-Ghaf-Queue-Position", str(position))
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # --- routing -------------------------------------------------------------

    def do_GET(self):
        if self.path.startswith("/v1/boot/"):
            return self.serve_boot_api(self.path[len("/v1/boot/") :])

        mac = self._client_mac()

        if self.path.endswith(IMAGE_SUFFIX):
            return self.serve_image(mac)

        # Tier 1: kernel, initrd, bmap. Never queued, and not attributed -- see
        # Fleet.ORDER for why.
        return super().do_GET()

    # A range this small cannot be a real download, so it is treated as an
    # admission probe: answered from the current occupancy without consuming a
    # turn. ghaf-installer's wait_for_image_slot() sends `Range: bytes=0-0`.
    PROBE_MAX_BYTES: ClassVar[int] = 1 << 20

    def parse_range(self):
        """Return (start, end_inclusive) for a single byte range, else None.

        Deliberately minimal: one range, no suffix form. Anything this does not
        understand falls through to a normal full-body response, which is always
        a correct answer to a Range request.
        """
        header = self.headers.get("Range")
        if not header:
            return None
        match = re.match(r"^bytes=(\d+)-(\d*)$", header.strip())
        if not match:
            return None
        start = int(match.group(1))
        end = int(match.group(2)) if match.group(2) else None
        return start, end

    def serve_range(self, path, start, end):
        """Send one byte range as 206. Used for the admission probe."""
        try:
            size = os.path.getsize(path)
        except OSError:
            self.send_error(404, "not found")
            return
        if start >= size:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        last = size - 1 if end is None else min(end, size - 1)
        length = last - start + 1
        self.send_response(206)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Range", f"bytes {start}-{last}/{size}")
        self.send_header("Content-Length", str(length))
        self.end_headers()
        with open(path, "rb") as fh:
            fh.seek(start)
            self.wfile.write(fh.read(length))

    def serve_image(self, mac):
        """Tier 2. Admission-controlled; the ONLY path that can be refused.

        Occupancy is checked for probes as well as downloads -- that is what
        makes the probe meaningful -- but a probe releases its slot as soon as it
        has sent its handful of bytes. Without the Range handling below a probe
        would take a slot AND start streaming 10.5 GB before the client killed
        it, so queued clients polling every 30 s would steal turns from the
        clients actually installing.
        """
        path = self.translate_path(self.path)
        rng = self.parse_range()
        probe = False
        if rng is not None:
            start, end = rng
            probe = end is not None and (end - start + 1) <= self.PROBE_MAX_BYTES

        if not type(self).image_slots.acquire(blocking=False):
            type(self).fleet.mark(mac, "queued")
            self.log_message(
                "image busy (%d in flight), queueing %s%s",
                type(self).max_images,
                mac or self.client_address[0],
                " (probe)" if probe else "",
            )
            self._send_503(position=type(self).max_images)
            return None

        try:
            if rng is not None:
                # Answer the range whether or not it is probe-sized; a real
                # ranged download is rare here but must not be mishandled.
                self.serve_range(path, *rng)
                return None

            type(self).fleet.mark(mac, "downloading")
            result = super().do_GET()
            type(self).fleet.mark(mac, "complete")
            self.log_message(
                "image served in full to %s", mac or self.client_address[0]
            )

            if type(self).fleet.roster_complete():
                sys.stderr.write(
                    "ghaf-netboot: ROSTER COMPLETE -- every allowlisted machine has "
                    "fetched the image\n"
                )
                sys.stderr.flush()

            # Single-machine mode only. With a fleet this would shut the server
            # down for everyone else the moment the first client finished; it is
            # refused alongside --mac-file/--any-mac in ghaf-netboot.sh. It is
            # only safe to remove because ghaf-installer now sets the target's
            # own BootNext/BootOrder, so a server that keeps running no longer
            # means a reinstall loop.
            if type(self).exit_after_serve:
                self.log_message("image served in full, shutting down")
                # shutdown() blocks until serve_forever() returns, so it can
                # never be called from a request thread -- hence the extra one.
                threading.Thread(target=self.server.shutdown, daemon=True).start()
            return result
        finally:
            # Must run even when the client pulls its cable mid-transfer, or a
            # dead client would hold a slot for the rest of the run.
            type(self).image_slots.release()

    def copyfile(self, source, outputfile):
        """Send with sendfile(2) where possible.

        SimpleHTTPRequestHandler copies through Python in 64 KB chunks. For a
        10.5 GB image times N concurrent clients that is a great deal of pointless
        userspace work; the kernel can do it without the round trip.
        """
        try:
            in_fd = source.fileno()
            out_fd = outputfile.fileno()
            offset = source.tell()
            remaining = os.fstat(in_fd).st_size - offset
        except (AttributeError, OSError, io.UnsupportedOperation):
            return super().copyfile(source, outputfile)

        try:
            while remaining > 0:
                sent = os.sendfile(out_fd, in_fd, offset, min(remaining, 1 << 24))
                if sent == 0:
                    break
                offset += sent
                remaining -= sent
        except OSError:
            # Includes the client disconnecting mid-transfer. Falling back would
            # re-send from the wrong place, so just stop; the client retries.
            return None
        return None

    def serve_boot_api(self, raw_mac):
        mac = normalise_mac(raw_mac)
        if mac is None:
            self.send_error(400, "malformed MAC")
            return
        if not type(self).any_mac and mac not in type(self).allowed:
            # 404 is Pixiecore's "ignore this machine". This is the allowlist.
            self.log_message("ignoring %s (not in allowlist)", mac)
            self.send_error(404, "not allowlisted")
            return

        # Attributed to the MAC pixiecore named, never to the peer address --
        # that is pixiecore itself. See _client_mac.
        type(self).fleet.mark(mac, "offered")

        body = json.dumps(type(self).boot_json).encode()
        self.log_message("booting %s", mac)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def arp_lookup(ip):
    """Peer IP -> MAC from /proc/net/arp, or None.

    Read every time rather than cached: a fleet run lasts hours, leases move,
    and a stale mapping would attribute one machine's progress to another --
    worse than reporting none.
    """
    try:
        with open("/proc/net/arp") as fh:
            rows = fh.readlines()[1:]
    except OSError:
        return None
    for row in rows:
        fields = row.split()
        if len(fields) < 4 or fields[0] != ip:
            continue
        mac = normalise_mac(fields[3])
        # An incomplete entry is all zeroes; it means "asked, no answer yet".
        if mac and mac != "00:00:00:00:00:00":
            return mac
    return None


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True
    # socketserver's default is 5. A hundred machines PXE booting together
    # produce far more than five near-simultaneous SYNs, and the excess is
    # refused by the kernel before this process ever sees it -- which looks like
    # a client-side network fault and is not one.
    request_queue_size = 512

    def handle_error(self, request, client_address):
        # A client vanishing mid-download is routine at fleet scale (a machine
        # reboots into its installed system) and must not print a traceback per
        # occurrence; anything else still should.
        exc = sys.exc_info()[1]
        if isinstance(exc, (BrokenPipeError, ConnectionResetError, socket.timeout)):
            return
        super().handle_error(request, client_address)


def progress_reporter(fleet, interval):
    def run():
        while True:
            time.sleep(interval)
            sys.stderr.write(f"ghaf-netboot: {fleet.summary()}\n")
            sys.stderr.flush()

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    return thread


def read_mac_file(path):
    """Parse a roster file: one MAC per line, # comments, blank lines ignored."""
    try:
        with open(path) as fh:
            lines = fh.readlines()
    except OSError as exc:
        # ghaf-netboot.sh checks this too, but the API is also started directly
        # by the NixOS module, where a bad path would otherwise surface as a
        # traceback in the journal rather than as a reason.
        sys.exit(f"ghaf-netboot: cannot read --mac-file {path}: {exc.strerror}")

    macs = []
    for lineno, raw in enumerate(lines, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        mac = normalise_mac(line)
        if mac is None:
            sys.exit(f"ghaf-netboot: {path}:{lineno}: not a MAC address: {line}")
        macs.append(mac)
    return macs


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
    ap.add_argument(
        "--mac-file", help="file of allowlisted MACs, one per line, # comments"
    )
    ap.add_argument(
        "--any-mac",
        action="store_true",
        help="serve every PXE client (isolated provisioning segment only)",
    )
    ap.add_argument("--cmdline", required=True, help="kernel command line")
    ap.add_argument(
        "--exit-after-serve",
        action="store_true",
        help="stop once the image has been fetched in full (single machine only)",
    )
    ap.add_argument(
        "--max-concurrent-images",
        type=int,
        default=8,
        help="how many clients may download the image at once (default 8)",
    )
    ap.add_argument(
        "--retry-after",
        type=int,
        default=30,
        help="seconds to tell a queued client to wait (default 30)",
    )
    ap.add_argument(
        "--progress-interval",
        type=int,
        default=60,
        help="seconds between fleet progress lines, 0 to disable (default 60)",
    )
    args = ap.parse_args()

    if args.max_concurrent_images < 1:
        sys.exit("ghaf-netboot: --max-concurrent-images must be at least 1")

    Handler.exit_after_serve = args.exit_after_serve
    Handler.any_mac = args.any_mac
    Handler.max_images = args.max_concurrent_images
    Handler.image_slots = threading.BoundedSemaphore(args.max_concurrent_images)
    Handler.retry_after = max(1, args.retry_after)

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
    if args.mac_file:
        macs.update(read_mac_file(args.mac_file))
    Handler.allowed = frozenset(macs)

    if not macs and not args.any_mac:
        # Fail closed. An empty allowlist that silently served everyone would be
        # the exact failure this component exists to prevent.
        sys.exit("ghaf-netboot: refusing to start with an empty MAC allowlist")

    # A roster is what makes "the fleet is done" knowable. --any-mac has none by
    # construction, so it never reports completion.
    Handler.fleet = Fleet(roster=() if args.any_mac else macs)

    if args.progress_interval > 0:
        progress_reporter(Handler.fleet, args.progress_interval)

    os.chdir(args.root)
    with Server((args.listen, args.port), Handler) as httpd:
        allowlist = "ANY (open serving)" if args.any_mac else " ".join(sorted(macs))
        print(
            f"ghaf-netboot: HTTP on {base}, serving {args.root}, "
            f"allowlist: {allowlist}, "
            f"image slots: {args.max_concurrent_images}",
            file=sys.stderr,
            flush=True,
        )
        httpd.serve_forever()


if __name__ == "__main__":
    main()

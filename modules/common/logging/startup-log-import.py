# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import argparse
import contextlib
import ctypes
import datetime
import json
import os
import subprocess
from pathlib import Path

FIELDS = (
    "MESSAGE,PRIORITY,_BOOT_ID,_COMM,SYSLOG_IDENTIFIER,_SYSTEMD_USER_UNIT,"
    "_SYSTEMD_UNIT,USER_UNIT,UNIT,_TRANSPORT"
)
SERVICE_FIELDS = (
    "UNIT",
    "USER_UNIT",
    "_SYSTEMD_UNIT",
    "_SYSTEMD_USER_UNIT",
    "SYSLOG_IDENTIFIER",
    "_COMM",
)


def field(entry, name):
    value = entry.get(name, "")
    if isinstance(value, list) and all(isinstance(v, int) for v in value):
        return bytes(value).decode("utf-8", errors="replace")
    return value if isinstance(value, str) else ""


def journal(boot, *matches):
    command = [
        "journalctl",
        f"--boot={boot}",
        "--no-pager",
        "--output=json",
        "--all",
        f"--output-fields={FIELDS}",
    ]
    with subprocess.Popen(command + list(matches), stdout=subprocess.PIPE) as process:
        try:
            while line := process.stdout.readline(8 * 1024 * 1024 + 1):
                if not line.endswith(b"\n"):
                    raise ValueError("journal record exceeds the 8 MiB input limit")
                yield json.loads(line)
            if process.wait():
                raise RuntimeError("Could not read startup journal records")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()


def startup_entry(entry):
    timestamp = int(entry["__REALTIME_TIMESTAMP"])
    original = datetime.datetime.fromtimestamp(
        timestamp // 1_000_000, datetime.UTC
    ).strftime("%Y-%m-%dT%H:%M:%S")
    original += f".{timestamp % 1_000_000:06d}Z"
    return {
        "MESSAGE": f"[original_timestamp={original}] {field(entry, 'MESSAGE')}",
        "GHAF_STARTUP_LOG": "1",
        "GHAF_STARTUP_SERVICE": next(
            (field(entry, name) for name in SERVICE_FIELDS if field(entry, name)), ""
        ),
        "GHAF_STARTUP_TRANSPORT": field(entry, "_TRANSPORT"),
        "PRIORITY": field(entry, "PRIORITY") or "6",
    }


class IOVec(ctypes.Structure):
    _fields_ = [("base", ctypes.c_char_p), ("length", ctypes.c_size_t)]


def send_entry(sendv, entry):
    fields = [f"{key}={value}".encode() for key, value in startup_entry(entry).items()]
    vectors = (IOVec * len(fields))(*(IOVec(value, len(value)) for value in fields))
    result = sendv(vectors, len(vectors))
    if result < 0:
        raise OSError(-result, os.strerror(-result))


@contextlib.contextmanager
def publish(path):
    temporary = path.with_suffix(".tmp")
    try:
        with temporary.open("wb") as stream:
            yield stream
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        descriptor = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        temporary.unlink(missing_ok=True)


def import_startup_logs(boot, directory, sendv):
    checkpoint = directory / "completed-boot"
    if checkpoint.exists() and checkpoint.read_text() == boot:
        return
    # Drain the clock gate's stdout before reading its journal marker.
    subprocess.run(["journalctl", "--sync"], check=True)
    with contextlib.closing(
        journal(boot, "_SYSTEMD_UNIT=ghaf-wait-time-sync.service")
    ) as markers:
        for marker in markers:
            if not field(marker, "MESSAGE").startswith(
                "Clock synchronised; realtime is "
            ):
                continue
            boundary = int(marker["__MONOTONIC_TIMESTAMP"])
            cutoff = int(marker["__REALTIME_TIMESTAMP"]) - 900_000_000
            break
        else:
            raise RuntimeError("The clock synchronization marker is missing")

    count = 0
    with contextlib.closing(journal(boot)) as entries:
        for entry in entries:
            if entry["__CURSOR"] == marker["__CURSOR"]:
                break
            if (
                int(entry["__MONOTONIC_TIMESTAMP"]) >= boundary
                or int(entry["__REALTIME_TIMESTAMP"]) >= cutoff
            ):
                continue
            send_entry(sendv, entry)
            count += 1
        else:
            raise RuntimeError(
                "The startup journal no longer contains the clock marker"
            )
    subprocess.run(["journalctl", "--sync"], check=True)
    with publish(checkpoint) as stream:
        stream.write(boot.encode())
    print(
        f"Requeued {count} old startup records through the journal; startup import complete"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--libsystemd", required=True)
    args = parser.parse_args()
    sendv = ctypes.CDLL(args.libsystemd).sd_journal_sendv
    sendv.argtypes = [ctypes.POINTER(IOVec), ctypes.c_int]
    sendv.restype = ctypes.c_int
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip().replace("-", "")
    import_startup_logs(boot, Path(os.environ["STATE_DIRECTORY"]), sendv)


if __name__ == "__main__":
    main()

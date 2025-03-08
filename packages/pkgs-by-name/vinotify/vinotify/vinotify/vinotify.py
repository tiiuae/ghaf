# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import logging
import os
import socket

from inotify_simple import INotify, flags

logger = logging.getLogger("vinotify")


def send_path(path, cid, port):
    try:
        with socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM) as s:
            s.connect((cid, port))
            message = f"{path}\n"
            s.sendall(message.encode())
    except Exception as e:
        logger.error(f"Failed to send message: {e}")


def host_mode(root_dir, cid, port):
    inotify = INotify()
    watch_descriptors = {}
    inotify_flags = (
        flags.CREATE | flags.DELETE | flags.MODIFY | flags.MOVED_FROM | flags.MOVED_TO
    )
    wd = inotify.add_watch(root_dir, inotify_flags)
    watch_descriptors[wd] = root_dir

    for root, dirs, files in os.walk(root_dir):
        for dirname in dirs:
            full_path = os.path.join(root, dirname)
            wd = inotify.add_watch(full_path, inotify_flags)
            watch_descriptors[wd] = full_path
            logger.info(f"Monitoring {full_path}")

    while True:
        events_to_send = set()
        for event in inotify.read(1000, 100):
            logger.debug(event)
            directory = watch_descriptors.get(event.wd)
            if directory and event.name:
                filepath = os.path.join(directory, event.name)
                relative_dir = os.path.relpath(directory, root_dir)
                if event.mask & flags.CREATE:
                    if event.mask & flags.ISDIR:
                        logger.info(f'New directory: "{filepath}"')
                        wd = inotify.add_watch(filepath, inotify_flags)
                        watch_descriptors[wd] = filepath
                    else:
                        logger.info(f'New file: "{filepath}"')
                        events_to_send.add(relative_dir)
                if event.mask & flags.DELETE:
                    if event.mask & flags.ISDIR:
                        logger.info(f'Deleted directory: "{filepath}"')
                        for wd, dir_path in list(watch_descriptors.items()):
                            if dir_path.startswith(filepath):
                                logger.info(
                                    f'Removing "{dir_path}" from the monitoring list'
                                )
                                del watch_descriptors[wd]
                                break
                    else:
                        logger.info(f'Delete: "{filepath}"')
                        events_to_send.add(relative_dir)
                if event.mask & flags.MOVED_TO:
                    logger.info(f'Moved to: "{filepath}"')
                    events_to_send.add(relative_dir)

        # Send all events to the guest
        for path in events_to_send:
            logger.info(f'Sending "{path}"')
            send_path(path, cid, port)
        events_to_send.clear()


def guest_mode(path, port):
    with socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM) as server:
        server.bind((socket.VMADDR_CID_ANY, port))
        server.listen()
        logger.info(f"Listening for events on port {port}")

        while True:
            conn, _ = server.accept()
            with conn:
                message = conn.recv(4097).decode().strip()
                if message:
                    filepath = os.path.join(path, message)
                    logger.info(f'Received "{message}", full path "{filepath}"')
                    try:
                        stat_info = os.stat(filepath)
                        os.utime(filepath, (stat_info.st_atime, stat_info.st_mtime))
                    except Exception as e:
                        logger.error(f"Error: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Monitor host directory and forward inotify events to guest over vsock"
    )
    parser.add_argument("--cid", type=int, required=False, help="The CID of guest VM")
    parser.add_argument("--port", type=int, required=True, help="VSOCK port")
    parser.add_argument("--path", type=str, required=True, help="Path to monitor")
    parser.add_argument(
        "--mode",
        type=str,
        choices=["guest", "host"],
        required=True,
        help="Run mode: guest or host",
    )
    parser.add_argument(
        "-d",
        "--debug",
        default=False,
        action=argparse.BooleanOptionalAction,
        help="Enable debug messages",
    )
    args = parser.parse_args()

    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s %(message)s"))
    logger.addHandler(handler)
    if args.debug:
        logger.setLevel(logging.DEBUG)
    else:
        logger.setLevel(logging.INFO)

    logger.info(f"Running vinotify on {args.path}")

    try:
        if args.mode == "host":
            if not args.cid:
                logger.error("--cid is required in host mode")
                return
            else:
                host_mode(args.path, args.cid, args.port)
        elif args.mode == "guest":
            guest_mode(args.path, args.port)
    except KeyboardInterrupt:
        logger.info("Ctrl+C")

    logger.info("Exiting")

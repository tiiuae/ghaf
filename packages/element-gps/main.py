#!/usr/bin/env python

# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import asyncio
import functools
import json
import signal
import threading

import websockets


class GpsProcessState:
    def __init__(self):
        self._gps_data = str()
        self.data_lock = asyncio.Lock()
        self.condition = asyncio.Condition()
        self.abort_websockets = False
        self.terminate = asyncio.Event()
        self.stop_event = threading.Event()
        self.stop_wait_asyncio = asyncio.get_event_loop().run_in_executor(
            None, self.stop_event.wait
        )

    def get_data(self):
        return self._gps_data

    def set_data(self, value):
        self._gps_data = value

    def del_data(self):
        del self._gps_data

    message = property(get_data, set_data, del_data)


async def read_continuous_gps(data):
    process = await asyncio.create_subprocess_exec(
        "gpspipe", "-w", stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE
    )
    print("GPS reader process PID:", {process.pid}, "starting...")

    while not data.terminate.is_set():
        if process.returncode is not None:
            print("gpspipe process has exited")
            break

        line = await process.stdout.readline()
        line = line.decode()

        if len(line) != 0:
            reply_json = json.loads(line)
            if reply_json["class"] == "TPV":
                async with data.data_lock:
                    data.message = line
                async with data.condition:
                    data.condition.notify_all()

    print("Closing service...")
    # Notify all websockets to quit
    async with data.condition:
        data.abort_websockets = True
        data.condition.notify_all()
        await asyncio.sleep(2)
        data.stop_event.set()


async def handler(websocket, path, gps_state):
    print("New connection received")
    while not gps_state.abort_websockets:
        async with gps_state.condition:
            await gps_state.condition.wait()
            if gps_state.abort_websockets:
                break
            async with gps_state.data_lock:
                output = gps_state.message
            try:
                await websocket.send(output)
            except Exception:
                print("Client disconnected.")
                break
    print("Closing websocket...")


async def wait_connection(gps_state):
    print("Websocket listener on localhost:8000.")
    async with websockets.serve(
        functools.partial(handler, gps_state=gps_state), "localhost", 8000
    ):
        await gps_state.stop_wait_asyncio
    print("Closing websocket listener.")


def signal_handler(signum, frame, state_object):
    # ignore additional signals
    signal.signal(signum, signal.SIG_IGN)
    state_object.terminate.set()


async def main():
    gps_state = GpsProcessState()
    # The stop condition is set when receiving SIGTERM or SIGINT.
    signal.signal(
        signal.SIGINT, functools.partial(signal_handler, state_object=gps_state)
    )
    signal.signal(
        signal.SIGTERM, functools.partial(signal_handler, state_object=gps_state)
    )
    await asyncio.gather(read_continuous_gps(gps_state), wait_connection(gps_state))


if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    stop = loop.create_future()
    loop.add_signal_handler(signal.SIGTERM, stop.set_result, None)
    try:
        loop.run_until_complete(main())
    finally:
        loop.close()

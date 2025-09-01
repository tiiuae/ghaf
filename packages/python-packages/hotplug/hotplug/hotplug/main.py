# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import asyncio
import json
import logging
import os
import re
import sys
from dataclasses import asdict, dataclass
from typing import TypeVar

from qemu.qmp import QMPClient, QMPError
from systemd.journal import JournalHandler

# Set up a logger with a systemd identifier
logger = logging.getLogger("hotplug")


class SystemdIdentifierFilter(logging.Filter):
    def filter(self, record):
        record.SYSLOG_IDENTIFIER = "hotplug"
        return True


@dataclass
class PciDevice:
    """A dataclass to represent a device that has been detached."""

    vendor_product_id: str
    qdev_id: str
    bus_id: str


@dataclass
class UsbDevice:
    """A dataclass to represent a device that has been detached."""

    bus_port_id: str
    qdev_id: str


T = TypeVar("T")  # generic type variable


def _get_pci_state_file_path(data_path: str) -> str:
    """Constructs the full path for the state file."""
    return os.path.join(data_path, "pci_devices_state.json")


def _get_usb_state_file_path(data_path: str) -> str:
    """Constructs the full path for the state file."""
    return os.path.join(data_path, "usb_devices_state.json")


# mapping from class to state file path getter
_STATE_FILE_MAP = {
    "PciDevice": _get_pci_state_file_path,
    "UsbDevice": _get_usb_state_file_path,
}


def _delete_state_file[T](data_path: str, cls: type[T]):
    """Deletes the state file if it exists."""
    state_file_func = _STATE_FILE_MAP.get(cls.__name__)
    if not state_file_func:
        raise ValueError(f"Unsupported device class: {cls.__name__}")

    state_file = state_file_func(data_path)

    if os.path.exists(state_file):
        try:
            os.remove(state_file)
            logger.debug(f"Removed existing state file: {state_file}")
        except OSError as e:
            logger.error(f"Failed to delete state file {state_file}: {e}")


def _read_state[T](data_path: str, cls: type[T]) -> list[T]:
    """Reads the state file and returns its content as a list of device objects (PciDevice, UsbDevice)."""
    state_file_func = _STATE_FILE_MAP.get(cls.__name__)
    if not state_file_func:
        raise ValueError(f"Unsupported device class: {cls.__name__}")

    state_file = state_file_func(data_path)
    if not os.path.exists(state_file):
        return []

    try:
        with open(state_file) as f:
            data = json.load(f)
            return [cls(**item) for item in data]
    except (OSError, json.JSONDecodeError, TypeError) as e:
        logger.error(f"Could not read or parse state file {state_file}: {e}")
        return []


def _write_state(data_path: str, devices: list[T], cls: type[T]):
    """Writes the given list of device objects (PciDevice, UsbDevice) to the state file."""
    state_file_func = _STATE_FILE_MAP.get(cls.__name__)
    if not state_file_func:
        raise ValueError(f"Unsupported device class: {cls.__name__}")

    state_file = state_file_func(data_path)
    try:
        os.makedirs(os.path.dirname(state_file), exist_ok=True)
        data_to_write = [asdict(device) for device in devices]
        with open(state_file, "w") as f:
            json.dump(data_to_write, f, indent=2)
        logger.debug(
            f"Wrote state for {len(devices)} {cls.__name__}(s) to {state_file}"
        )
    except OSError as e:
        logger.error(f"Could not write to state file {state_file}: {e}")
        sys.exit(1)


def _find_qmp_device_in_bus(
    devices: list, target_vendor_id: int, target_product_id: int, parent_bus_id: str
) -> tuple[str | None, str | None]:
    """Recursively searches a QMP PCI device list for a matching vendor/product ID."""
    for device in devices:
        device_ids = device.get("id", {})
        if (
            device_ids.get("vendor") == target_vendor_id
            and device_ids.get("device") == target_product_id
        ):
            qdev_id = device.get("qdev_id")
            if qdev_id:
                logger.debug(
                    f"Found matching device in VM: qdev_id='{qdev_id}' on bus '{parent_bus_id}'"
                )
                return qdev_id, parent_bus_id

        if "pci_bridge" in device:
            bridge_qdev_id = device.get("qdev_id")
            if bridge_qdev_id:
                bridge_devices = device["pci_bridge"].get("devices", [])
                found_id, found_bus = _find_qmp_device_in_bus(
                    bridge_devices, target_vendor_id, target_product_id, bridge_qdev_id
                )
                if found_id:
                    return found_id, found_bus

    return None, None


def _find_host_pci_address(vendor_id: int, product_id: int) -> str | None:
    """Scans /sys to find a host PCI address for a given vendor/product ID, preferring vfio-pci."""
    pci_devices_path = "/sys/bus/pci/devices"
    try:
        for device_dir in os.listdir(pci_devices_path):
            device_path = os.path.join(pci_devices_path, device_dir)
            try:
                with open(os.path.join(device_path, "vendor")) as f:
                    current_vendor = int(f.read().strip(), 16)
                with open(os.path.join(device_path, "device")) as f:
                    current_product = int(f.read().strip(), 16)

                if current_vendor == vendor_id and current_product == product_id:
                    driver_path = os.path.join(device_path, "driver")
                    if (
                        os.path.islink(driver_path)
                        and os.path.basename(os.readlink(driver_path)) == "vfio-pci"
                    ):
                        logger.debug(
                            f"Found available host device {device_dir} for {vendor_id:04x}:{product_id:04x}"
                        )
                        return device_dir
            except (OSError, ValueError):
                continue
    except FileNotFoundError:
        logger.error(f"Host PCI path not found: {pci_devices_path}")

    return None


async def handle_detach_pci(
    qmp: QMPClient, vendor_product_ids: list[str], data_path: str
):
    """Finds devices by their vendor/product IDs, detaches them, and records their info."""
    logger.debug(f"Attempting to detach {len(vendor_product_ids)} device(s)...")
    _delete_state_file(data_path, PciDevice)

    successfully_detached: list[PciDevice] = []
    pci_info = await qmp.execute("query-pci")

    for vp_id in vendor_product_ids:
        try:
            vendor_str, product_str = vp_id.split(":")
            target_vendor_id = int(vendor_str, 16)
            target_product_id = int(product_str, 16)
        except ValueError:
            logger.error(f"Invalid format for vendor:product ID '{vp_id}'. Skipping.")
            continue

        qdev_id, bus_id = None, None
        for bus in pci_info:
            qdev_id, bus_id = _find_qmp_device_in_bus(
                bus.get("devices", []),
                target_vendor_id,
                target_product_id,
                bus.get("bus"),
            )
            if qdev_id:
                break

        if not qdev_id:
            logger.debug(f"Device '{vp_id}' not found attached to the VM. Skipping.")
            continue

        logger.debug(f"Detaching device '{vp_id}' (QEMU ID: '{qdev_id}')")
        try:
            await qmp.execute("device_del", {"id": qdev_id})
            successfully_detached.append(PciDevice(vp_id, qdev_id, bus_id))
        except QMPError as e:
            logger.error(f"Failed to detach device '{qdev_id}': {e}")

    if successfully_detached:
        _write_state(data_path, successfully_detached, PciDevice)
        logger.info(
            f"Successfully detached and saved state for {len(successfully_detached)} device(s)."
        )
    else:
        logger.warning("No devices were detached.")


async def handle_attach_pci(qmp: QMPClient, data_path: str):
    """Attaches all devices listed in the state file."""
    devices_to_attach = _read_state(data_path, PciDevice)
    if not devices_to_attach:
        logger.info("No detached devices found in state. Nothing to do.")
        _delete_state_file(data_path, PciDevice)
        return

    logger.info(
        f"Attempting to attach {len(devices_to_attach)} device(s) from state..."
    )
    devices_not_attached = devices_to_attach.copy()

    for device in devices_to_attach:
        try:
            vendor_str, product_str = device.vendor_product_id.split(":")
            vendor_id = int(vendor_str, 16)
            product_id = int(product_str, 16)
        except ValueError:
            logger.error(
                f"Invalid vendor:product ID '{device.vendor_product_id}' in state. Skipping."
            )
            continue

        host_pci_addr = _find_host_pci_address(vendor_id, product_id)
        if not host_pci_addr:
            logger.error(
                f"Could not find an available host device for '{device.vendor_product_id}'. Skipping."
            )
            continue

        attach_args = {
            "driver": "vfio-pci",
            "host": host_pci_addr,
            "id": device.qdev_id,
            "bus": device.bus_id,
        }
        logger.debug(f"Attaching device {host_pci_addr} with args: {attach_args}")
        try:
            await qmp.execute("device_add", attach_args)
            logger.debug(
                f"Successfully sent attach command for device '{host_pci_addr}'."
            )
            devices_not_attached.remove(device)
        except QMPError as e:
            logger.error(f"Failed to attach device '{host_pci_addr}': {e}")

    if devices_not_attached:
        logger.warning(
            f"{len(devices_not_attached)} device(s) could not be re-attached."
        )
    else:
        logger.info("All devices attached successfully.")

    # Cleanup
    _delete_state_file(data_path, PciDevice)


async def handle_detach_usb(qmp: QMPClient, bus_port_qid: list[str], data_path: str):
    """Finds device by their vendor/product/Qemu IDs, detaches them, and records their info."""
    logger.debug(f"Attempting to detach {len(bus_port_qid)} device(s)...")
    _delete_state_file(data_path, UsbDevice)

    successfully_detached: list[UsbDevice] = []

    for bpq_id in bus_port_qid:
        try:
            hostbus, hostport, qdev_id = bpq_id.split(":")
        except ValueError:
            logger.error(f"Invalid format for bus:port ID '{bpq_id}'. Skipping.")
            continue

        usb_info = await qmp.execute("x-query-usb")
        ids = re.findall(r"ID:\s*(\S+)", usb_info["human-readable-text"])

        if qdev_id not in ids:
            logger.debug(f"Device '{bpq_id}' not found attached to the VM. Skipping.")
            continue

        logger.debug(f"Detaching device '{hostbus}:{hostport}' (QEMU ID: '{qdev_id}')")
        try:
            await qmp.execute("device_del", {"id": qdev_id})
            successfully_detached.append(UsbDevice(hostbus + ":" + hostport, qdev_id))
        except QMPError as e:
            logger.error(f"Failed to detach device '{qdev_id}': {e}")

        if successfully_detached:
            _write_state(data_path, successfully_detached, UsbDevice)
            logger.info(
                f"Successfully detached and saved state for {len(successfully_detached)} device(s)."
            )
        else:
            logger.warning("No devices were detached.")


async def handle_attach_usb(qmp: QMPClient, data_path: str):
    """Attaches all devices listed in the state file."""
    devices_to_attach = _read_state(data_path, UsbDevice)
    if not devices_to_attach:
        logger.info("No detached devices found in state. Nothing to do.")
        _delete_state_file(data_path, UsbDevice)
        return

    logger.info(
        f"Attempting to attach {len(devices_to_attach)} device(s) from state..."
    )
    devices_not_attached = devices_to_attach.copy()

    for device in devices_to_attach:
        try:
            hostbus_str, hostport_str = device.bus_port_id.split(":")
            hostbus_id = int(hostbus_str, 16)
            qdev_id = device.qdev_id
        except ValueError:
            logger.error(
                f"Invalid bus:port ID '{device.bus_port_id}' in state. Skipping."
            )
            continue

    attach_args = {
        "driver": "usb-host",
        "hostbus": hostbus_id,
        "hostport": hostport_str,
        "id": qdev_id,
    }
    logger.debug(f"Attaching device with args: {attach_args}")
    try:
        await qmp.execute("device_add", attach_args)
        logger.debug(f"Successfully sent attach command for device '{device}'.")
        devices_not_attached.remove(device)
    except QMPError as e:
        logger.error(f"Failed to attach device '{device}': {e}")

    if devices_not_attached:
        logger.warning(
            f"{len(devices_not_attached)} device(s) could not be re-attached."
        )
    else:
        logger.info("All devices attached successfully.")

    # Cleanup
    _delete_state_file(data_path, UsbDevice)


async def main_async(args: argparse.Namespace):
    """Main asynchronous logic."""
    logger.debug(f"Starting execution with args: {args}")

    if not os.path.isdir(args.data_path):
        try:
            os.makedirs(args.data_path)
        except OSError as e:
            logger.error(f"Failed to create state directory {args.data_path}: {e}")
            sys.exit(1)

    qmp = QMPClient("hotplug")
    try:
        logger.debug(f"Connecting to QEMU monitor at {args.socket_path}")
        await qmp.connect(args.socket_path)

        if args.detach_pci:
            await handle_detach_pci(qmp, args.detach_pci, args.data_path)
        elif args.attach_pci:
            await handle_attach_pci(qmp, args.data_path)
        elif args.detach_usb:
            await handle_detach_usb(qmp, args.detach_usb, args.data_path)
        elif args.attach_usb:
            await handle_attach_usb(qmp, args.data_path)

    except FileNotFoundError:
        logger.error(
            f"QEMU socket not found at '{args.socket_path}'. Is the VM running?"
        )
        sys.exit(1)
    except QMPError as e:
        logger.error(f"QMP communication error: {e}")
        sys.exit(1)
    except Exception:
        logger.exception("An unexpected error occurred.")
        sys.exit(1)
    finally:
        await qmp.disconnect()
        logger.debug("Execution finished.")


def main():
    """Synchronous entry point, argument parsing, and logging setup."""
    parser = argparse.ArgumentParser(
        description="Attach or detach a PCI device from a running QEMU VM.",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable detailed debug logging."
    )
    parser.add_argument(
        "--socket-path", required=True, help="Path to the QEMU monitor UNIX socket."
    )
    parser.add_argument(
        "--data-path",
        required=True,
        help="Path to the directory for storing the device state file.",
    )
    action_group = parser.add_mutually_exclusive_group(required=True)
    action_group.add_argument(
        "--detach-pci",
        metavar="VENDOR:PRODUCT",
        nargs="+",
        help="Detach one or more devices by vendor:product ID (e.g., '8086:a1c1').",
    )
    action_group.add_argument(
        "--attach-pci",
        action="store_true",
        help="Attach all devices recorded in the state file.",
    )
    action_group.add_argument(
        "--detach-usb",
        metavar="VENDOR:PRODUCT",
        nargs="+",
        help="Detach one or more devices by vendor:product ID (e.g., '04f2:b729').",
    )
    action_group.add_argument(
        "--attach-usb",
        action="store_true",
        help="Attach all devices recorded in the state file.",
    )
    args = parser.parse_args()

    # Configure logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    formatter = logging.Formatter("%(message)s")
    journal_handler = JournalHandler()
    journal_handler.setFormatter(formatter)
    logger.addHandler(journal_handler)
    logger.setLevel(log_level)
    logger.addFilter(SystemdIdentifierFilter())

    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        logger.info("Operation cancelled by user.")
        sys.exit(130)


# For manual testing, you can run this script directly
if __name__ == "__main__":
    main()

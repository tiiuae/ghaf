# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import fcntl
import logging
import sys
import time
from pathlib import Path

import pyudev

logger = logging.getLogger("vhwdetect")

EVIOCGNAME = 0x81004506
EVIOCGUNIQ = 0x81004508


def is_input_device(device):
    if (
        device.subsystem == "input"
        and device.sys_name.startswith("event")
        and device.properties.get("ID_INPUT") == "1"
    ):
        return (
            device.properties.get("ID_INPUT_MOUSE") == "1"
            or (device.properties.get("ID_INPUT_KEYBOARD") == "1")
            or (device.properties.get("ID_INPUT_TOUCHPAD") == "1")
            or (device.properties.get("ID_INPUT_TOUCHSCREEN") == "1")
            or (device.properties.get("ID_INPUT_TABLET") == "1")
        )
    return False


def get_evdev_name(device):
    if device.device_node:
        with open(device.device_node, "rb") as dev:
            name = bytearray(256)
            fcntl.ioctl(dev, EVIOCGNAME, name)
            return name.split(b"\x00", 1)[0].decode("utf-8")
    else:
        return None


def get_evdev_serial(device):
    if device.device_node:
        with open(device.device_node, "rb") as dev:
            serial = bytearray(256)
            try:
                fcntl.ioctl(dev, EVIOCGUNIQ, serial)
                return serial.split(b"\x00", 1)[0].decode("utf-8")
            except OSError as e:
                if e.errno != 2:
                    logger.error(f"EVIOCGUNIQ failed: {e}")
                return None
    else:
        return None


def log_device(device, level=logging.DEBUG):
    try:
        logger.log(level, f"Device path: {device.device_path}")
        logger.log(level, f"  sys_path: {device.sys_path}")
        logger.log(level, f"  sys_name: {device.sys_name}")
        logger.log(level, f"  sys_number: {device.sys_number}")
        logger.log(level, "  tags:")
        for t in device.tags:
            if t:
                logger.log(level, f"    {t}")
        logger.log(level, f"  subsystem: {device.subsystem}")
        logger.log(level, f"  driver: {device.driver}")
        logger.log(level, f"  device_type: {device.device_type}")
        logger.log(level, f"  device_node: {device.device_node}")
        logger.log(level, f"  device_number: {device.device_number}")
        logger.log(level, f"  is_initialized: {device.is_initialized}")
        logger.log(level, "  Device properties:")
        for i in device.properties:
            logger.log(level, f"    {i} = {device.properties[i]}")
        logger.log(level, "  Device attributes:")
        for a in device.attributes.available_attributes:
            logger.log(level, f"    {a}: {device.attributes.get(a)}")
    except AttributeError as e:
        logger.warn(e)


def vmm_args_evdev(vmm, device):
    if vmm == "qemu":
        return f"-device virtio-input-host-pci,evdev={device.device_node}"
    elif vmm == "crosvm":
        return f"--input evdev[path={device.device_node}]"
    elif vmm == "cloud-hypervisor":
        logger.warning("Cloud Hypervisor doesn't support evdev passthrough")
        return ""
    else:
        logger.debug(f"Unknown VMM: {vmm}")
        return ""


def vmm_args_pci(vmm, device):
    if vmm is None:
        return ""
    elif vmm == "qemu":
        return f"-device vfio-pci,host={device.sys_name},multifunction=on"
    elif vmm == "crosvm":
        return f"--vfio /sys/bus/pci/devices/{device.sys_name},iommu=viommu"
    elif vmm == "cloud-hypervisor":
        return f"--device path=/sys/bus/pci/devices/{device.sys_name}"
    else:
        logger.debug(f"Unknown VMM: {vmm}")
        return ""


def unbind_driver(device_path, device):
    for attempt in range(1, 5):
        try:
            with open(device_path / "driver/unbind", "w") as f:
                f.write(device.sys_name)
            logger.info(
                f"Successfully unbound {device.driver} driver from {device_path}"
            )
            break
        except Exception as e:
            logger.warning(
                f"Failed to unbind {device.driver} driver from {device_path}: {e}"
            )
        time.sleep(1)
    else:
        logger.error(
            f"Failed to unbind {device.driver} from {device_path} after 5 attempts"
        )


def setup_vfio(device):
    try:
        device_path = Path(f"/sys/bus/pci/devices/{device.sys_name}")
        if not device_path.exists():
            logger.error(f"Device path {device_path} does not exist")
            return

        if (device_path / "driver").exists():
            unbind_driver(device_path, device)

        with open(device_path / "driver_override", "w") as f:
            f.write("vfio-pci")

        with open("/sys/bus/pci/drivers_probe", "w") as f:
            f.write(device.sys_name)

        # Wait for IOMMU group to appear
        for attempt in range(1, 5):
            iommu_group = device_path / "iommu_group"
            if not iommu_group.exists():
                logger.warning("IOMMU group does not exist")
                time.sleep(0.1)
            else:
                logger.info(f"IOMMU group: {iommu_group.resolve().name}")
                break

        logger.info(f"Successfully bound vfio-pci driver to {device_path}")
    except OSError as e:
        logger.error(f"Failed to setup VFIO for {device_path}: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Detect passthrough-capable hardware and generate VMM launch arguments"
    )
    parser.add_argument(
        "--vmm",
        choices=["qemu", "crosvm"],
        required=False,
        help="Target VMM (qemu or crosvm)",
    )
    parser.add_argument(
        "--devices", nargs="+", required=True, help="Types of devices to passthrough"
    )
    parser.add_argument(
        "--vfio-setup",
        default=False,
        action=argparse.BooleanOptionalAction,
        help="Enable VFIO PCI setup",
    )
    parser.add_argument(
        "-d",
        "--debug",
        default=False,
        action=argparse.BooleanOptionalAction,
        help="Enable debug messages",
    )
    args = parser.parse_args()

    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(levelname)s %(message)s"))
    logger.addHandler(handler)
    if args.debug:
        logger.setLevel(logging.DEBUG)
    else:
        logger.setLevel(logging.INFO)
    logger.info("Scanning hardware")

    vmm_args = []

    # Evdev passthrough
    if "input" in args.devices:
        context = pyudev.Context()
        for device in context.list_devices(subsystem="input"):
            bus = device.properties.get("ID_BUS")
            if is_input_device(device) and bus != "usb":
                name = get_evdev_name(device)
                serial = get_evdev_serial(device)
                logger.info(
                    f"Found non-USB input device: {name}, node: {device.device_node}, serial: {serial}, bus: {bus}"
                )
                vmm_args.append(vmm_args_evdev(args.vmm, device))

    # PCI passthrough
    pci_devices = {}
    if (
        "display" in args.devices
        or "audio" in args.devices
        or "network" in args.devices
    ):
        context = pyudev.Context()
        host_pci_devices = context.list_devices(subsystem="pci")
        for device in host_pci_devices:
            sys_name = device.sys_name
            driver = device.driver
            pci_id = device.properties.get("PCI_ID")
            vendor_id, device_id = pci_id.split(":")
            pci_class_hex = device.properties.get("PCI_CLASS")
            pci_class_dec = int(pci_class_hex, 16)
            pci_class = (pci_class_dec >> 16) & 0xFF
            pci_subclass = (pci_class_dec >> 8) & 0xFF
            # log_device(device)

            if pci_class == 0x03 and "display" in args.devices:
                logger.info(
                    f"Found display device {sys_name} ({pci_id}), driver: {driver}, class: {pci_class}, subclass: {pci_subclass}"
                )
                pci_devices[device.sys_name] = {
                    "type": "display",
                    "device": device,
                }
            elif pci_class == 0x02 and "network" in args.devices:
                logger.info(
                    f"Found network device {sys_name} ({pci_id}), driver: {driver}, class: {pci_class}, subclass: {pci_subclass}"
                )
                pci_devices[device.sys_name] = {
                    "type": "network",
                    "device": device,
                }
            elif pci_class == 0x04 and pci_subclass == 0x03 and "audio" in args.devices:
                logger.info(
                    f"Found audio device {sys_name} ({pci_id}), driver: {driver}, class: {pci_class}, subclass: {pci_subclass}"
                )
                pci_devices[device.sys_name] = {
                    "type": "audio",
                    "device": device,
                }
                # Hack: For Intel HD Audio controllers, we pass additional devices to the audio VM
                if vendor_id == "8086" and sys_name == "0000:00:1f.3":
                    for dev in host_pci_devices:
                        if dev.sys_name == "0000:00:1f.0":  # LPC Controller
                            logger.info("Found Intel LPC Controller")
                            pci_devices[dev.sys_name] = {
                                "type": "audio",
                                "device": dev,
                            }
                        elif dev.sys_name == "0000:00:1f.4":  # SMBus Host Controller
                            logger.info("Found Intel SMBus Host Controller")
                            pci_devices[dev.sys_name] = {
                                "type": "audio",
                                "device": dev,
                            }
                        elif dev.sys_name == "0000:00:1f.5":  # SPI Controller
                            logger.info("Found Intel SPI Controller")
                            pci_devices[dev.sys_name] = {
                                "type": "audio",
                                "device": dev,
                            }

    # Build vmm arguments for selected PCI devices
    guest_addrs = []
    for dev_name, dev_info in pci_devices.items():
        dev_type = dev_info["type"]
        device = dev_info["device"]

        if args.vfio_setup and device.driver != "vfio-pci":
            logger.info(f"Setting up VFIO bindings for {dev_name}")
            setup_vfio(device)

        pci_args = vmm_args_pci(args.vmm, device)
        if args.vmm == "qemu" and dev_type == "display":
            # The x-igd-opregion property exposes opregion (VBT included) to guest driver
            # so that the guest driver could parse display connector information from
            # This is required to enable DisplayPort over USB-C
            pci_args = pci_args + ",x-igd-opregion=on"
        if args.vmm == "crosvm":
            # Crosvm uses the host device name, which might have a function not equal to 0
            # In this case, we either need to pass the .0 device as well or set a guest address with .0
            # Otherwise, the PCI bus in the guest won't be able to detect the device
            domain_bus_dev, func = dev_name.rsplit(".", 1)
            func = int(func)
            if func != 0:
                new_addr = f"{domain_bus_dev}.0"
                if new_addr not in pci_devices and new_addr not in guest_addrs:
                    pci_args = pci_args + f",guest-address={new_addr}"
                    guest_addrs.append(new_addr)

        vmm_args.append(pci_args)

    logger.info("Finished hardware scan")
    if args.vmm is not None:
        print(" ".join(vmm_args))
    sys.exit(0)

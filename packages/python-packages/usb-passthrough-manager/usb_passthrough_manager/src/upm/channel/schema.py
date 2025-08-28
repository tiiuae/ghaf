# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

from typing import Any

# Valid schema
# - device_connected: {"type":"device_connected","device":{ "device_id":"vid:pid", "vendor":"vendor_name", "product":"product_name", "permitted-vms": ["vm1" "vm2"], "current-vm":"vm-name"}}
# - selection: {"type":"selection","device_id":"vid:pid","target_vm":"vm-name"}
# - device_removed: {"type":"device_removed","device_id":"vid:pid"}


def validate_schema(doc: dict[str, Any]) -> bool:
    if not isinstance(doc, dict):
        doc = {}

    stype = doc.get("type", "")
    if stype == "device_connected":
        device = doc.get("device", {})
        if not isinstance(device, dict):
            return False
        else:
            if (
                "device_id" in device
                and "vendor" in device
                and "product" in device
                and "permitted-vms" in device
                and "current-vm" in device
            ):
                return True
            else:
                return False
    if stype == "selection":
        if "device_id" in doc and "target_vm" in doc:
            return True
        else:
            return False
    if stype == "device_removed":
        if "device_id" in doc:
            return True
        else:
            return False
    return False

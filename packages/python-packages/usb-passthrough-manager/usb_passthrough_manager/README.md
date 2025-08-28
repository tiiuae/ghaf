<!--
    Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# USB Passthrough Manager

Host ↔ guest VM with real user, usb passthrough management over vsock with a PyQt5 UI
develop without vsock by using a JSON file as the “transport”.

## Install (editable)
```bash
pip install -e ".[usb_passthrough_manager]"
```

On COSMIC/Wayland you may want:

```bash
export QT_QPA_PLATFORM=wayland
```

## Schema

```json
{
  "1a86:7523": {
    "permitted-vms": ["vm-a", "vm-b", "vm-x"],
    "vendor": "QinHeng",
    "product": "CH340 Serial",
    "current-vm": "vm-a"
  },
  "046d:0825": {
    "permitted-vms": ["vm-a", "vm-c", "vm-d"],
    "vendor": "Logitech",
    "product": "Webcam C270",
    "current-vm": "vm-c"
  }
}

```

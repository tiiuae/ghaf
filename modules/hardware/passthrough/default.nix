# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  imports = [
    ./evdev-rules.nix
    ./passthrough.nix
    ./pci-acs-override/pci-acs-override.nix
    ./pci-ports.nix
    ./pci-rules.nix
    ./usb-quirks.nix
    ./usb-rules.nix
    ./usb-static.nix
    ./vhotplug.nix
  ];
}

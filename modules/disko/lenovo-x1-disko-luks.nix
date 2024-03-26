# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  environment.systemPackages = [pkgs.fido2luks];
  boot.initrd.luks.fido2Support = true;
  boot.initrd.luks.devices.encrypted.fido2.credentials = ["b610d7d28dc9f3a87a643e2be6f35df7c7faaa09c2439bbc3679ffd07b726c46898e49f7ac9a1feeed872cea91d830b8"];
  boot.initrd.luks.devices.encrypted.fido2.passwordLess = true;
  boot.initrd.luks.devices.encrypted.fallbackToPassword = true;
}

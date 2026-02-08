# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  _file = ./default.nix;

  imports = [
    ./audio
    ./bluetooth.nix
    ./brightness.nix
    ./createFakeBattery.nix
    ./disks.nix
    ./firmware.nix
    ./fprint.nix
    ./github.nix
    ./hwinfo
    ./killswitch.nix
    ./locale.nix
    ./performance
    ./power.nix
    ./storewatcher.nix
    ./sssd.nix
    ./timezone.nix
    ./user-provision.nix
    ./wifi.nix
    ./xpadneo.nix
    ./yubikey.nix
  ];
}

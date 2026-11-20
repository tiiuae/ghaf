# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
let
  mkFlasher =
    name:
    pkgs.writeShellApplication {
      inherit name;
      text = ''printf '%s\n' ${name} "$@"'';
    };
  mkWrapper =
    defaultStorage: names:
    import ../modules/reference/hardware/jetpack/nvidia-jetson-orin/verity-flash-wrapper.nix {
      inherit pkgs defaultStorage;
      flashers = pkgs.lib.genAttrs names mkFlasher;
    };
  agx = mkWrapper "emmc" [
    "emmc"
    "nvme"
    "usb"
  ];
  nx = mkWrapper "nvme" [
    "nvme"
    "usb"
  ];
in
pkgs.runCommand "orin-flash-storage" { } ''
  test "$(${pkgs.lib.getExe agx})" = emmc
  test "$(${pkgs.lib.getExe nx})" = nvme
  for storage in emmc nvme usb; do
    test "$(${pkgs.lib.getExe agx} --storage "$storage" | head -1)" = "$storage"
  done
  test "$(${pkgs.lib.getExe nx} --storage usb | head -1)" = usb
  ${pkgs.lib.getExe nx} --secure-boot --storage usb --disk /dev/disk/by-id/usb-test --usb-instance 3-3 >args
  printf '%s\n' usb --disk /dev/disk/by-id/usb-test --usb-instance 3-3 >expected
  cmp args expected
  if ${pkgs.lib.getExe nx} --storage emmc; then exit 1; fi
  if ${pkgs.lib.getExe agx} --storage; then exit 1; fi
  if ${pkgs.lib.getExe agx} --storage sata; then exit 1; fi
  touch "$out"
''

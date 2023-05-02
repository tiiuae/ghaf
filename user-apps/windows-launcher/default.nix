# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  ...
}: let
  windowsLauncher =
    pkgs.writeShellScript
    "windows-launcher"
    ''
      if [ $# -eq 0 ]; then
        echo "Usage: windows-launcher ./Windows11_InsiderPreview_Client_ARM64_en-us_25324.VHDX"
        exit
      fi

      if [[ -z "''${WAYLAND_DISPLAY}" ]]; then
        echo "Wayland display not found"
        exit
      fi

      IMG_DIR="$(dirname "$1")"
      AAVMF_VARS="$IMG_DIR/AAVMF_VARS.fd"

      if [ ! -f $AAVMF_VARS ]; then
        cp ${pkgs.OVMF.fd}/FV/AAVMF_VARS.fd $AAVMF_VARS
        chmod 644 $AAVMF_VARS
      fi

      ${pkgs.qemu}/bin/qemu-system-aarch64 \
        -name "Windows VM" \
        -M virt,highmem=on,gic-version=max \
        -cpu host \
        -enable-kvm \
        -smp 6 \
        -m 12G \
        -drive file=${pkgs.OVMF.fd}/FV/AAVMF_CODE.fd,format=raw,if=pflash,readonly=on \
        -drive file=$AAVMF_VARS,format=raw,if=pflash \
        -device ramfb \
        -device virtio-gpu-pci \
        -device qemu-xhci \
        -device usb-kbd \
        -device usb-tablet \
        -drive file=$1,format=vhdx,if=none,id=boot \
        -device usb-storage,drive=boot,serial=boot \
        -nic user,model=virtio \
        ''${@:2}
    '';
  windowsLauncherUI =
    pkgs.writeShellScript
    "windows-launcher-ui"
    ''
      if [[ -z "''${WAYLAND_DISPLAY}" ]]; then
        echo "Wayland display not found"
        exit
      fi

      CONFIG=~/.config/windows-launcher-ui.conf
      if [ -f "$CONFIG" ]; then
        source $CONFIG
      fi

      if [ ! -f "$FILE" ]; then
        FILE=`${pkgs.gnome.zenity}/bin/zenity --file-selection --title="Select Windows VM image (VHDX)"`
        if [ ''$? -ne 0 ]; then
          exit
        else
          echo FILE="$FILE" > "$CONFIG"
        fi
      fi

      if ! ${windowsLauncher} $FILE; then
        ${pkgs.gnome.zenity}/bin/zenity --error --text="Failed to run Windows VM: $?"
      fi
    '';
in
  stdenvNoCC.mkDerivation {
    name = "windows-launcher";

    buildInputs = [pkgs.gnome.zenity];

    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp ${windowsLauncher} $out/bin/windows-launcher
      cp ${windowsLauncherUI} $out/bin/windows-launcher-ui
    '';

    meta = with lib; {
      description = "Helper scripts for launching Windows ARM64 virtual machines using QEMU";
      platforms = [
        "aarch64-linux"
      ];
    };
  }

# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  stdenv,
  ...
}: let
  ovmfPrefix =
    if stdenv.isx86_64
    then "OVMF"
    else if stdenv.isAarch64
    then "AAVMF"
    else throw "Unsupported architecture";
  windowsLauncher =
    pkgs.writeShellScript
    "windows-launcher"
    (''
        IMG_FILE=$1
        ISO_FILE=""
        if [ $# -eq 0 ]; then
      ''
      + lib.optionalString stdenv.isAarch64 ''
        echo "Usage: windows-launcher ./Windows11_InsiderPreview_Client_ARM64_en-us_25324.VHDX"
      ''
      + lib.optionalString stdenv.isx86_64 ''
        echo "Usage: windows-launcher ./Win11_22H2_English_x64v2.iso or ./win11.qcow2"
      ''
      + ''
          exit
        fi

        if [[ -z "''${WAYLAND_DISPLAY}" ]]; then
          echo "Wayland display not found"
          exit
        fi

        IMG_DIR="$(dirname "$IMG_FILE")"
        OVMF_VARS="$IMG_DIR/${ovmfPrefix}_VARS.fd"
        OVMF_CODE="$IMG_DIR/${ovmfPrefix}_CODE.fd"

        if [ ! -f $OVMF_VARS ] || [ ! -f $OVMF_CODE ]; then
          cp ${pkgs.OVMF.fd}/FV/${ovmfPrefix}_VARS.fd $OVMF_VARS
          cp ${pkgs.OVMF.fd}/FV/${ovmfPrefix}_CODE.fd $OVMF_CODE
          chmod 644 $OVMF_VARS
        fi
      ''
      + lib.optionalString stdenv.isx86_64 ''
        if [[ $1 == *.iso || $1 == *.ISO ]]; then
          ISO_FILE=$1
          IMG_FILE="$IMG_DIR/win11.qcow2"
          if [ ! -f $IMG_FILE ]; then
            ${pkgs.qemu}/bin/qemu-img create -f qcow2 $IMG_FILE 64G
          fi
        fi
      ''
      + ''
        QEMU_PARAMS=(
          "-name \"Windows VM\""
          "-cpu host"
          "-enable-kvm"
          "-smp 6"
          "-m 8G"
          "-drive file=$OVMF_CODE,format=raw,if=pflash,readonly=on"
          "-drive file=$OVMF_VARS,format=raw,if=pflash"
          "-vga none"
          "-device ramfb"
          "-device virtio-gpu-pci"
          "-device qemu-xhci"
          "-device usb-kbd"
          "-device usb-tablet"
          "-nic user,model=virtio"
      ''
      + lib.optionalString stdenv.isAarch64 ''
        "-M virt,highmem=on,gic-version=max"
        "-drive file=$IMG_FILE,format=vhdx,if=none,id=boot"
        "-device usb-storage,drive=boot,serial=boot,bootindex=1"
        )
      ''
      + lib.optionalString stdenv.isx86_64 ''
        "-drive file=$IMG_FILE,format=qcow2,if=none,id=boot"
        "-device nvme,drive=boot,serial=boot,bootindex=1"
        )

        if [ ! -z "$ISO_FILE" ]; then
          QEMU_PARAMS+=(
            "-drive file=$ISO_FILE,media=cdrom,if=none,id=installcd"
            "-device usb-storage,drive=installcd,bootindex=0"
          )
        fi
      ''
      + ''
        eval "${pkgs.qemu}/bin/qemu-system-${stdenv.hostPlatform.qemuArch} ''${QEMU_PARAMS[@]} ''${@:2}"
      '');
  windowsLauncherUI =
    pkgs.writeShellScript
    "windows-launcher-ui"
    (''
        if [[ -z "''${WAYLAND_DISPLAY}" ]]; then
          echo "Wayland display not found"
          exit
        fi

        CONFIG=~/.config/windows-launcher-ui.conf
        if [ -f "$CONFIG" ]; then
          source $CONFIG
        fi

        if [ ! -f "$FILE" ]; then
      ''
      + lib.optionalString stdenv.isAarch64 ''
        FILE=`${pkgs.gnome.zenity}/bin/zenity --file-selection --title="Select Windows VM image (VHDX)"`
      ''
      + lib.optionalString stdenv.isx86_64 ''
        FILE=`${pkgs.gnome.zenity}/bin/zenity --file-selection --title="Select Windows VM image (QCOW2 or ISO)"`
      ''
      + ''
          if [ ''$? -ne 0 ]; then
            exit
          else
            if [[ $FILE != *.iso && $FILE != *.ISO ]]; then
              echo FILE="$FILE" > "$CONFIG"
            fi
          fi
        fi

        if ! ${windowsLauncher} $FILE; then
          ${pkgs.gnome.zenity}/bin/zenity --error --text="Failed to run Windows VM: $?"
        fi
      '');
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
      description = "Helper scripts for launching Windows virtual machines using QEMU";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }

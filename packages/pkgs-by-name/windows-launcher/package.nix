# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  lib,
  stdenv,
  qemu_kvm,
  OVMF,
  yad,
  writeShellApplication,
  enableSpice ? false,
}:
let
  ovmfPrefix =
    if stdenv.isx86_64 then
      "OVMF"
    else if stdenv.isAarch64 then
      "AAVMF"
    else
      throw "Unsupported architecture";
  windowsLauncher = writeShellApplication {
    name = "windows-launcher";
    runtimeInputs = [ qemu_kvm ];
    text = ''
      if [ $# -eq 0 ]; then
    ''
    + lib.optionalString stdenv.isAarch64 ''
      echo "Usage: windows-launcher ./Windows11_InsiderPreview_Client_ARM64_en-us_25324.VHDX"
    ''
    + lib.optionalString stdenv.isx86_64 ''
      echo "Usage: windows-launcher ./Win11_22H2_English_x64v2.iso or ./win11.qcow2"
    ''
    + ''
        exit 1
      fi
      IMG_FILE=$1
      ISO_FILE=""
    ''
    + lib.optionalString (!enableSpice) ''
      if [[ -z "''${WAYLAND_DISPLAY:-}" ]]; then
        echo "Wayland display not found"
        exit 1
      fi
    ''
    + ''
      IMG_DIR="$(dirname "$IMG_FILE")"
      OVMF_VARS="$IMG_DIR/${ovmfPrefix}_VARS.fd"
      OVMF_CODE="$IMG_DIR/${ovmfPrefix}_CODE.fd"

      if [ ! -f "$OVMF_VARS" ] || [ ! -f "$OVMF_CODE" ]; then
        cp ${OVMF.fd}/FV/${ovmfPrefix}_VARS.fd "$OVMF_VARS"
        cp ${OVMF.fd}/FV/${ovmfPrefix}_CODE.fd "$OVMF_CODE"
        chmod 644 "$OVMF_VARS"
      fi
    ''
    + lib.optionalString stdenv.isx86_64 ''
      if [[ $1 == *.iso || $1 == *.ISO ]]; then
        ISO_FILE=$1
        IMG_FILE="$IMG_DIR/win11.qcow2"
        if [ ! -f "$IMG_FILE" ]; then
          qemu-img create -f qcow2 "$IMG_FILE" 64G
        fi
      fi
    ''
    + ''
      QEMU_PARAMS=(
        -name "Windows VM"
        -cpu host
        -enable-kvm
        -smp 6
        -m 8G
        -drive "file=$OVMF_CODE,format=raw,if=pflash,readonly=on"
        -drive "file=$OVMF_VARS,format=raw,if=pflash"
      )
    ''
    + lib.optionalString (!enableSpice) ''
      QEMU_PARAMS+=(
        -vga none
        -device ramfb
        -device virtio-gpu-pci
        -nic "user,model=virtio"
      )
    ''
    + lib.optionalString enableSpice ''
      QEMU_PARAMS+=(
        -vga qxl
        -device virtio-serial-pci
        -spice "port=5900,addr=0.0.0.0,disable-ticketing=on"
        -netdev "tap,id=tap-windows,ifname=tap-windows,script=no,downscript=no"
        -device "e1000,netdev=tap-windows,mac=02:00:00:03:55:01"
      )
    ''
    + ''
      QEMU_PARAMS+=(
        -device qemu-xhci
        -device usb-kbd
        -device usb-tablet
      )
    ''
    + lib.optionalString stdenv.isAarch64 ''
      QEMU_PARAMS+=(
        -M "virt,highmem=on,gic-version=max"
        -drive "file=$IMG_FILE,format=vhdx,if=none,id=boot"
        -device "usb-storage,drive=boot,serial=boot,bootindex=1"
      )
    ''
    + lib.optionalString stdenv.isx86_64 ''
      QEMU_PARAMS+=(
        -drive "file=$IMG_FILE,format=qcow2,if=none,id=boot"
        -device "nvme,drive=boot,serial=boot,bootindex=1"
      )

      if [ -n "$ISO_FILE" ]; then
        QEMU_PARAMS+=(
          -drive "file=$ISO_FILE,media=cdrom,if=none,id=installcd"
          -device "usb-storage,drive=installcd,bootindex=0"
        )
      fi
    ''
    + ''
      # Arguments are passed as array elements, never through eval/word
      # splitting: image paths with shell metacharacters stay inert.
      exec qemu-kvm "''${QEMU_PARAMS[@]}" "''${@:2}"
    '';
  };
  windowsLauncherUI = writeShellApplication {
    name = "windows-launcher-ui";
    runtimeInputs = [ yad ];
    text = ''
      if [[ -z "''${WAYLAND_DISPLAY:-}" ]]; then
        echo "Wayland display not found"
        exit 1
      fi

      CONFIG="$HOME/.config/windows-launcher-ui.conf"
      FILE=""
      if [ -f "$CONFIG" ]; then
        # The config stores only the image path; it is data, never sourced.
        FILE=$(<"$CONFIG")
      fi

      if [ ! -f "$FILE" ]; then
    ''
    + lib.optionalString stdenv.isAarch64 ''
      if ! FILE=$(yad --file --title="Select Windows VM image (VHDX)"); then
        exit 0
      fi
    ''
    + lib.optionalString stdenv.isx86_64 ''
      if ! FILE=$(yad --file --title="Select Windows VM image (QCOW2 or ISO)"); then
        exit 0
      fi
    ''
    + ''
        if [[ $FILE != *.iso && $FILE != *.ISO ]]; then
          printf '%s\n' "$FILE" > "$CONFIG"
        fi
      fi

      if ! ${lib.getExe windowsLauncher} "$FILE"; then
        yad --image=gtk-dialog-error --text="Failed to run Windows VM"
      fi
    '';
  };
in
stdenvNoCC.mkDerivation {
  name = "windows-launcher";

  buildInputs = [
    yad
    qemu_kvm
    OVMF
  ];

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${lib.getExe windowsLauncher} $out/bin/windows-launcher
    cp ${lib.getExe windowsLauncherUI} $out/bin/windows-launcher-ui
  '';

  meta = {
    description = "Helper scripts for launching Windows virtual machines using QEMU";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}

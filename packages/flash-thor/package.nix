# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Thor NVMe flash script package. Requires usb gadget counterpart
# that provides the internal nvme device.
#
{
  writeShellApplication,
  coreutils,
  util-linux,
  zstd,
  findutils,
  e2fsprogs,
  gptfdisk,
  # Required arguments for the flash script
  jetpackFlashScript,
  sdImage,
  fileName,
}:
writeShellApplication {
  name = "flash-thor";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    findutils
    e2fsprogs
    gptfdisk
  ];
  text = ''
    export JETPACK_FLASH_SCRIPT="${jetpackFlashScript}"
    export SD_IMAGE="${sdImage}"
    export IMAGE_NAME="${fileName}"
  ''
  + builtins.readFile ./flash-thor.sh;
  meta = {
    description = "Thor NVMe flash script for Ghaf";
    platforms = [ "x86_64-linux" ];
  };
}

# SPDX-FileCopyrightText: 2022-2023 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
_: {
  ghaf.installer.installerModules.flushImage = {
    requestCode = ''
      lsblk
      read -p "Device name [e.g. sda]: " DEVICE_NAME
    '';
    providedVariables = {
      deviceName = "$DEVICE_NAME";
    };
  };
}

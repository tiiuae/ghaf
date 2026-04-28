# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  ghaf.services.power-manager.suspend = {
    mode = lib.mkDefault "auto";
    s2idleModels = [ "System76 Darter Pro" ];
  };
}

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  _file = ./client.nix;

  options.ghaf.reference.services.proxy-client.enable =
    lib.mkEnableOption "use of the net-vm proxy server";
}

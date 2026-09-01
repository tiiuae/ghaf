# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  _file = ./orin-pkvm.nix;

  options.ghaf.host.kernel.hardening = {
    hypervisor.enable = lib.mkEnableOption "support for protected guests on Orin AGX";
  };
}

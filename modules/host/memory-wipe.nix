# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.host.memory-wipe;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.ghaf.host.memory-wipe = {
    enable = mkEnableOption "Memory wipe on boot and free using kernel parameters";
  };

  config = mkIf cfg.enable {
    boot.kernelPatches = [
      {
        name = "memory-wipe-config";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          # Enable page poisoning for additional security
          PAGE_POISONING = yes;

          # Enable init-on-alloc and init-on-free support
          INIT_ON_ALLOC_DEFAULT_ON = option yes;
          INIT_ON_FREE_DEFAULT_ON = option yes;
        };
      }
    ];
  };
}

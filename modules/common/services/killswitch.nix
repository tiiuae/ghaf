# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    ;
  cfg = config.ghaf.services.kill-switch;
in
{
  _file = ./killswitch.nix;

  options.ghaf.services.kill-switch.enable = mkEnableOption "ghaf kill switch support";

  # TODO: Currently enabled for x86_64, we will evaluate the need for aarch64 support in the future
  config = mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isx86_64) {
    # The panel applet and the ghaf-kill-switch command. They block devices by
    # detaching the passthrough devices tagged audio, net, cam and bt through
    # the device manager API.
    environment.systemPackages = [ pkgs.ghaf-kill-switch ];
  };
}

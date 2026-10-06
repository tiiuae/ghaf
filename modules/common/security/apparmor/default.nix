# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.security.apparmor;
in
{
  _file = ./default.nix;

  options.ghaf.security.apparmor.enable = lib.mkEnableOption "Apparmor security";

  imports = [
    ./profiles/google-chrome.nix
    ./profiles/ping.nix
  ];

  config = lib.mkIf cfg.enable {
    security = {
      apparmor = {
        enable = true;
        killUnconfinedConfinables = lib.mkDefault true;
      };
      # Keep AppArmor before BPF in the generated lsm= kernel parameter.
      lsm = lib.mkForce [
        "landlock"
        "yama"
        "apparmor"
        "bpf"
      ];
    };
    services.dbus.apparmor = "enabled";
  };
}

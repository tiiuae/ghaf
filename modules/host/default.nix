# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules that should be only imported to host
#
{ lib, pkgs, ... }:
{
  networking.hostName = lib.mkDefault "ghaf-host";

  # Overlays should be only defined for host, because microvm.nix uses the
  # pkgs that already has overlays in place. Otherwise the overlay will be
  # applied twice.
  nixpkgs.overlays = [ (import ../../overlays/custom-packages) ];
  imports = [
    # To push logs to central location
    ../common/logging/client.nix
  ];

  # Adding below systemd services to save power by turning off display when system is suspended / lid close
  systemd.services.display-suspend = {
    enable = true;
    description = "Display Suspend Service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''${pkgs.sshpass}/bin/sshpass -p ghaf ${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=no ghaf@gui-vm-debug WAYLAND_DISPLAY=/run/user/1000/wayland-0 wlopm --off \* '';
    };
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
  };

  systemd.services.display-resume = {
    enable = true;
    description = "Display Resume Service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''${pkgs.sshpass}/bin/sshpass -p ghaf ${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=no ghaf@gui-vm-debug WAYLAND_DISPLAY=/run/user/1000/wayland-0 wlopm --on \* '';
    };
    wantedBy = [ "suspend.target" ];
    after = [ "suspend.target" ];
  };
}

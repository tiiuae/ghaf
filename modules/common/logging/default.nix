# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  # Creating logging configuration options needed across the host and vms
  options.ghaf.logging = {
    client.enable = mkOption {
      description = ''
        Enable logging client service. Currently we have grafana alloy
        running as client which will upload system journal logs to
        grafana alloy running in admin-vm.
      '';
      type = types.bool;
      default = false;
    };

    listener.address = mkOption {
      description = ''
        Listener address will be used where log producers will
        push logs and where admin-vm alloy.service will be
        keep on listening or receiving logs.
      '';
      type = types.str;
    };

    listener.port = mkOption {
      description = ''
        Listener port for the logproto endpoint which will be
        used to receive logs from different log producers.
        Also this port value will be used to open the port in
        the admin-vm firewall.
      '';
      type = types.port;
      default = 9999;
    };
  };
}

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  # Creating logging configuration options needed across the host and vms
  options.ghaf.logging = {
    enable = mkOption {
      description = ''
        Enable logging service. Currently we have grafana alloy
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
      default = "";
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

    journalRetention = {
      enable = mkOption {
        description = ''
          Enable local journal retention configuration.
          This configures systemd-journald to retain logs locally for a specified period.
        '';
        type = types.bool;
        default = true;
      };

      maxRetentionDays = mkOption {
        description = ''
          Maximum number of days to retain journal logs locally.
          After this period, old logs will be deleted automatically.
        '';
        type = types.int;
        default = 30;
      };

      maxDiskUsage = mkOption {
        description = ''
          Maximum disk space that journal logs can occupy.
          Accepts sizes like "500M", "1G", etc.
        '';
        type = types.str;
        default = "500M";
      };
    };
  };
}

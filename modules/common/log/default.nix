# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}:
with lib; {
  options.ghaf.logging.client.enable = lib.mkOption {
    description = ''
      Enable logging client service. Currently we have grafana alloy
      running as client which will upload system journal logs to
      grafana loki running in admin-vm
    '';
    type = lib.types.bool;
    default = false;
  };

  options.ghaf.logging.port = lib.mkOption {
    description = ''
      Assign port value to grafana alloy process service running in
      admin-vm. Using this port value firewall allowed TCP port
      policy will be created Ghaf internally to grafana loki
      (by default in admin-vm). No external network firewall policies
      are created
    '';
    type = lib.types.int;
    default = 3100;
  };

  options.ghaf.logging.listener.port = lib.mkOption {
    description = ''
      Assign port value to grafana alloy source service running in
      different clients. Using this port value firewall allowed TCP port
      policy will be created Ghaf internally to grafana loki
      (by default in admin-vm). No external network firewall policies
      are created
    '';
    type = lib.types.int;
    default = 9999;
  };
}

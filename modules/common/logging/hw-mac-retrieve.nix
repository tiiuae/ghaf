# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # TODO: replace sshCommand and MacCommand with givc rpc to retrieve Mac Address
  sshCommand = "${pkgs.sshpass}/bin/sshpass -p ghaf ${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=no ghaf@net-vm";
  macCommand = "${pkgs.hwinfo}/bin/hwinfo --network --only /class/net/wlp0s5f0 |  ${pkgs.gawk}/bin/awk '/Permanent HW Address/ {print $4}'";
  macAddressPath = config.ghaf.logging.identifierFilePath;
in
{
  options.ghaf.logging.identifierFilePath = lib.mkOption {
    description = ''
      This configuration option used to specify the identifier file path.
      The identifier file will be text file which have unique identification
      value per machine so that when logs will be uploaded to cloud
      we can identify its origin.
    '';
    type = lib.types.path;
    example = "/tmp/MACAddress";
  };

  config = lib.mkIf config.ghaf.logging.client.enable {
    # TODO: Remove hw-mac.service and replace with givc rpc later
    systemd.services."hw-mac" = {
      description = "Retrieve MAC address from net-vm";
      wantedBy = [
        "alloy.service"
        "multi-user.target"
      ];
      requires = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        # Make sure we can ssh before we retrieve mac address
        ExecStartPre = "${sshCommand} ls";
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c "echo -n $(${sshCommand} ${macCommand}) > ${macAddressPath} "
        '';
        Restart = "on-failure";
        RestartSec = "1";
      };
    };
  };
}

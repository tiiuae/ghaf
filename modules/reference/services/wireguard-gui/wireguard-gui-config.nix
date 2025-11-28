# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.wireguard-gui-config;
  inherit (lib)
    mkOption
    mkIf
    types
    ;
  isGuiVM = "gui-vm" == config.system.name;
  isNetVM = "net-vm" == config.system.name;
  inherit (config.ghaf.networking) hosts;
  netVmInternalNic = hosts."net-vm".interfaceName;
in
{
  options.ghaf.reference.services.wireguard-gui-config = {
    enabledVmNames = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of VM names where Wireguard GUI should be enabled.";
      example = [
        "business-vm"
        "chrome-vm"
      ];
    };
    serverPortsByVm = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            vmName = mkOption {
              type = types.str;
              description = "VM name providing WireGuard server ports.";
            };

            serverPorts = mkOption {
              type = types.listOf types.port;
              default = [ ];
              description = "WireGuard server ports for this VM.";
            };
          };
        }
      );

      default = [ ];
      description = ''
        List of server ports per VM for Wireguard GUI.
        Each element has:
          - vmName (string)
          - serverPorts (list of integers)
      '';

      example = [
        {
          vmName = "business-vm";
          serverPorts = [
            51820
            51821
          ];
        }
        {
          vmName = "chrome-vm";
          serverPorts = [ 51822 ];
        }
      ];
    };
    netVmExternalNic = mkOption {
      type = types.str;
      default = "";
      description = ''
        External network interface
      '';
    };
  };

  config = {
    # Assert that all ports are unique
    assertions = [
      {
        assertion =
          let
            allPorts = lib.lists.concatMap (entry: entry.serverPorts) cfg.serverPortsByVm;
          in
          lib.length allPorts == lib.length (lib.lists.unique allPorts);

        message = "Duplicate WireGuard server ports detected across VMs! Each port must be unique.";
      }
    ];
    environment.etc."ctrl-panel/wireguard-gui-vms.txt" = mkIf isGuiVM (
      let
        vmstxt = lib.concatStringsSep "\n" cfg.enabledVmNames;
      in
      {
        text = ''
          ${vmstxt}
        '';
      }
    );
    ghaf.firewall.extra = mkIf isNetVM {
      forward.filter = lib.concatLists (
        map (
          vm:
          map (
            port: "-i ${cfg.netVmExternalNic} -o ${netVmInternalNic} -p udp --dport ${toString port} -j ACCEPT"
          ) vm.serverPorts
        ) cfg.serverPortsByVm
      );

      postrouting.nat = lib.concatLists (
        map (
          vm:
          map (
            port: "-o ${cfg.netVmExternalNic} -p udp --dport ${toString port} -j MASQUERADE"
          ) vm.serverPorts
        ) cfg.serverPortsByVm
      );
    };
    environment.etc."ctrl-panel/wireguard-TEST.txt" = mkIf isNetVM (
      let
        # Format each entry as: vmName: port1,port2,port3
        formatEntry =
          entry: "${entry.vmName}: ${lib.concatStringsSep "," (map toString entry.serverPorts)}";

        vmstxt = lib.concatStringsSep "\n" (
          builtins.trace (builtins.deepSeq cfg.serverPortsByVm cfg.serverPortsByVm) (
            map formatEntry cfg.serverPortsByVm
          )
        );
      in
      {
        text = ''
          ${vmstxt}
        '';
      }
    );
  };
}

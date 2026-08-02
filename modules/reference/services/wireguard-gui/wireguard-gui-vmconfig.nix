# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.wireguard-gui-vmconfig;
  inherit (lib)
    mkOption
    mkIf
    types
    lists
    ;
  isGuiVM = "gui-vm" == config.system.name;
  isNetVM = "net-vm" == config.system.name;
  inherit (config.ghaf.networking) hosts;
  netVmInternalNic = hosts."net-vm".interfaceName;
in
{
  _file = ./wireguard-gui-vmconfig.nix;

  options.ghaf.reference.services.wireguard-gui-vmconfig = {
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
            allPorts = lists.concatMap (entry: entry.serverPorts) cfg.serverPortsByVm;
          in
          lib.length allPorts == lib.length (lists.unique allPorts);

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
    # These rules name the LAN-facing interface, which is only known at runtime,
    # so they go through ghaf.firewall.uplink with @UPLINK@ standing in for it.
    #
    # Worth knowing before touching this: on every current target these two
    # lists are EMPTY. wireguard-gui is enabled on the host, gui-vm, business-vm
    # and chrome-vm but never in net-vm, and this block is `mkIf isNetVM`, so
    # serverPortsByVm is [] here and no WireGuard server port has ever actually
    # been DNAT'd. Switching that on is a security-relevant change -- it opens
    # new inbound paths into app-VMs -- and is deliberately NOT part of this
    # refactor. The migration below only ensures that if someone does enable it,
    # the rules name the interface that carries the LAN rather than the Wi-Fi
    # card the build happened to guess.
    ghaf.firewall = mkIf isNetVM {
      uplink = {
        enable = true;

        rules.forward.filter = lib.concatLists (
          map (
            vm:
            map (
              port:
              "-i @UPLINK@ -o ${netVmInternalNic} -p udp --dport ${toString port} -m comment --comment \"wg-server-${vm.vmName}\" -j ACCEPT"
            ) vm.serverPorts
          ) cfg.serverPortsByVm
        );

        rules.prerouting.nat = lib.concatLists (
          map (
            vm:
            map (
              port:
              "-i @UPLINK@ -p udp --dport ${toString port} -m comment --comment \"wg-server-${vm.vmName}\" -j DNAT --to-destination  ${hosts.${vm.vmName}.ipv4}:${toString port}"
            ) vm.serverPorts
          ) cfg.serverPortsByVm
        );
      };
    };
  };
}

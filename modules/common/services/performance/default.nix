# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.performance;

  tunedNoDesktop = pkgs.tuned.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -f "$out/share/applications/"*.desktop
    '';
  });

  inherit (lib)
    literalExpression
    mkIf
    mkOption
    types
    ;

  # General TuneD script generator
  # Here we can add helper functions which can be used in the scripts
  mkTunedScript =
    {
      name ? "tuned-script",
      start ? "",
      stop ? "",
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        tuned
        wirelesstools
      ];
      bashOptions = [ ];
      text = ''
        # shellcheck disable=SC1091
        source ${pkgs.tuned}/lib/tuned/functions

        # Set wireless power management
        wifi_set_pm() {
          # 'on' - enable power saving
          # 'off' - disable power saving
          pm=$1

          # do not report errors on systems with no wireless
          [ -e /proc/net/wireless ] || return 0

          # apply the settings using iwconfig
          ifaces=$(cat /proc/net/wireless | grep -v '|' | sed 's@^ *\([^:]*\):.*@\1@')

          for iface in $ifaces; do
            iwconfig "$iface" power "$pm"
          done
        }

        # Set PCI device runtime power management
        pci_device_runtime_pm() {
          # 'on' - best performance
          # 'auto' - best power saving

          pm=$1
          devices=$2

          for device in $devices; do
            (echo "$pm" > "/sys/bus/pci/devices/$device/power/control") &> /dev/null
          done
        }

        start() {
          ${if start == "" then "return 0" else start}
        }

        stop() {
          ${if stop == "" then "return 0" else stop}
        }

        process "$@"
      '';
    };

in
{
  _file = ./default.nix;

  imports = [
    (import ./host.nix {
      inherit
        pkgs
        config
        lib
        mkTunedScript
        tunedNoDesktop
        ;
    })
    (import ./guests.nix {
      inherit
        pkgs
        config
        lib
        mkTunedScript
        tunedNoDesktop
        ;
    })
  ];

  options.ghaf.services.performance = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable hardware-agnostic Ghaf performance and scheduler optimizations.

        For more information, see `tuned-main.conf(5)`, `tuned-profiles.7`,
        and system76-scheduler documentation.
      '';
      example = literalExpression ''
        # In host
        config.ghaf.services.performance = {
          enable = true;
          host.enable = true;
        };

        # In GUI VM
        config.ghaf.services.performance = {
          enable = true;
          gui.enable = true;
        };
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.hardware.system76.power-daemon.enable;
        message = "`config.ghaf.performance` conflicts with `config.hardware.system76.power-daemon.enable`.";
      }
      {
        assertion = cfg.vm.enable -> (!cfg.host.enable && !cfg.gui.enable);
        message = "Enabling the generic VM performance profile ('ghaf.services.performance.vm.enable') requires the 'host' and 'vm' profiles to be disabled.";
      }
    ];
  };
}

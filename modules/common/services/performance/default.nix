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
    cartesianProduct
    genAttrs
    getExe'
    listToAttrs
    literalExpression
    mkOption
    nameValuePair
    optionalString
    types
    ;

  # The six profiles every set has: three PPD levels x AC/battery. One source for
  # the profile list, the ppd.conf mapping and the GIVC unit names.
  mkProfileVariants =
    prefix:
    listToAttrs (
      map (v: nameValuePair "${prefix}-${v.base}${optionalString v.onBattery "-battery"}" v)
        (cartesianProduct {
          base = [
            "powersave"
            "balanced"
            "performance"
          ];
          onBattery = [
            false
            true
          ];
        })
    );

  # tuned-ppd's mapping from the three PPD levels to our profiles.
  mkPpdSettings = prefix: {
    main.default = "balanced";
    battery = {
      power-saver = "${prefix}-powersave-battery";
      balanced = "${prefix}-balanced-battery";
      performance = "${prefix}-performance-battery";
    };
    profiles = {
      power-saver = "${prefix}-powersave";
      balanced = "${prefix}-balanced";
      performance = "${prefix}-performance";
    };
  };

  # Started over GIVC by the gui-vm; whitelisted in modules/givc/<vm>.nix.
  mkPpdServices =
    location: names:
    genAttrs names (profile: {
      description = "Enable ${profile} Ghaf PPD profile on ${location}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${getExe' pkgs.tuned "tuned-adm"} profile ${profile}";
      };
    });

  # Each generated script is its own store path holding one profile directory.
  mkProfileDirs =
    scripts: "/etc/tuned/profiles,${lib.concatMapStringsSep "," toString (lib.attrValues scripts)}";

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
    ./host.nix
    ./guests.nix
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

  config = {
    # Passed as module arguments so the sub-modules stay real NixOS modules.
    _module.args = {
      inherit
        mkTunedScript
        tunedNoDesktop
        mkProfileVariants
        mkPpdSettings
        mkPpdServices
        mkProfileDirs
        ;
    };

    assertions = lib.optionals cfg.enable [
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

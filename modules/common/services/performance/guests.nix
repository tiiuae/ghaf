# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  mkTunedScript,
  tunedNoDesktop,
  mkProfileVariants,
  mkPpdSettings,
  mkPpdServices,
  mkProfileDirs,
  ...
}:
let
  cfg = config.ghaf.services.performance;
  inherit (lib)
    getExe
    getExe'
    mapAttrs
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalString
    removePrefix
    replaceString
    types
    ;

  guiProfileVariants = mkProfileVariants "gui";
  netProfileVariants = mkProfileVariants "net";

  useGivc = config.ghaf.givc.enable;

  givc-cli = "${getExe' pkgs.givc-cli "givc-cli"} ${
    replaceString "/run" "/etc" config.ghaf.givc.cliArgs
  }";

  guiVmSchedulerAssignments = {
    desktop-environment = {
      nice = -5;
      ioClass = "best-effort";
      ioPrio = 0;
      matchers = [
        "cosmic-comp"
      ];
    };
    waypipe = {
      nice = -3;
      ioClass = "best-effort";
      ioPrio = 2;
      matchers = [
        "waypipe"
      ];
    };
    sound-server = {
      nice = -15;
      ioClass = "realtime";
      ioPrio = 0;
      matchers = [
        "pipewire"
        "pipewire-pulse"
      ];
    };
    # Apps belonging to user
    # Minor prioritization
    # Should be removed when cosmic-comp supports foreground checking
    app-slice = {
      nice = -2;
      ioClass = "best-effort";
      ioPrio = 0;
      matchers = [
        "include cgroup=\"/user.slice/*slice/*service/*slice/*.scope\""
      ];
    };
    # Session services belonging to the user
    session-services = {
      nice = 5;
      ioClass = "idle";
      matchers = [
        "include cgroup=\"/user.slice/*.slice/*\""
        "exclude cgroup=\"/user.slice/*.slice/*.service/app.slice/*\""
      ];
    };
    # System services belonging to root
    system-services = {
      nice = 7;
      ioClass = "idle";
      matchers = [
        "include cgroup=\"/system.slice/*\""
        "exclude cgroup=\"/user.slice/*\" parent=\"systemd\""
      ];
    };
  };

  mkBrightnessScript = level: ''
    b=$(${getExe pkgs.brightnessctl} get)
    m=$(${getExe pkgs.brightnessctl} max)
    ((b*100/m>${toString level})) && ${getExe pkgs.brightnessctl} set ${toString level}%
  '';

  # For a general structure of the scripts, see:
  # https://github.com/redhat-performance/tuned/blob/master/profiles/powersave/script.sh
  #
  # gui-vm is where the profile is picked, so each one fans out over GIVC.
  guiProfileScripts =
    let
      # Panel brightness per profile; performance on AC leaves it alone.
      brightness = {
        gui-powersave = 40;
        gui-balanced = 70;
        gui-performance = null;
        gui-powersave-battery = 25;
        gui-balanced-battery = 50;
        gui-performance-battery = 70;
      };
      # VM to forward to, and the profile prefix that VM uses.
      forwardTo = {
        ghaf-host = "host";
        net-vm = "net";
      };
    in
    mapAttrs (
      name: _:
      mkTunedScript {
        inherit name;
        start =
          optionalString (brightness.${name} != null) (mkBrightnessScript brightness.${name})
          + optionalString useGivc (
            lib.concatStrings (
              lib.mapAttrsToList (vm: prefix: ''
                timeout 5s ${givc-cli} start service --vm "${vm}" ${prefix}-${removePrefix "gui-" name}.service &
              '') forwardTo
            )
          );
      }
    ) guiProfileVariants;

  netProfileScripts = {
    net-performance = mkTunedScript {
      name = "net-performance";
      start = ''
        wifi_set_pm off
      '';
      stop = ''
        wifi_set_pm on
      '';
    };
  };

  tunedProfiles = {
    vm = {
      main = {
        summary = "Ghaf TuneD profile for Virtual Machines";
        include = "virtual-guest";
      };
    };
  };
in
{
  _file = ./guests.nix;

  options.ghaf.services.performance = {
    gui = {
      enable = mkEnableOption "Ghaf-specific scheduler and power optimizations for gui-vm.";
      scheduler = {
        enable = mkEnableOption "system76-scheduler on gui-vm for Ghaf-specific process scheduling." // {
          default = false;
        };
      };
      tuned = {
        enable = mkEnableOption "TuneD service on the gui-vm for Ghaf-specific performance profiles." // {
          default = true;
        };
        defaultProfile = mkOption {
          type = types.str;
          default = "gui-balanced";
          description = "Default TuneD profile to use on gui-vm.";
        };
        profileNames = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = lib.attrNames guiProfileVariants;
          description = ''
            The profiles this module defines. GIVC whitelists the matching
            units so the gui-vm can select a profile here; read the list from
            this option rather than repeating it.
          '';
        };
      };
    };

    net = {
      enable = mkEnableOption "Ghaf-specific power optimizations for net-vm.";
      tuned = {
        enable = mkEnableOption "TuneD service on the net-vm for Ghaf-specific performance profiles." // {
          default = true;
        };
        defaultProfile = mkOption {
          type = types.str;
          default = "net-balanced";
          description = "Default TuneD profile to use on net-vm.";
        };
        profileNames = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = lib.attrNames netProfileVariants;
          description = ''
            The profiles this module defines. GIVC whitelists the matching
            units so the gui-vm can select a profile here; read the list from
            this option rather than repeating it.
          '';
        };
      };
    };

    vm = {
      enable = mkEnableOption ''
        Generalized Ghaf-specific power and performance optimizations for VMs.

        This will enable the general virtual-guest tuned profile statically -
        gui-vm power profile changes will not propagate to this VM and no custom scripts will be run.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.gui.enable {
      services.system76-scheduler = {
        inherit (cfg.gui.scheduler) enable;
        useStockConfig = false;
        settings = {
          processScheduler = {
            refreshInterval = 30;
            pipewireBoost.enable = false;
            # cosmic-comp still lacks integration with s76-scheduler
            foregroundBoost.enable = false;
            useExecsnoop = true;
          };
          cfsProfiles.enable = false;
        };
        assignments = guiVmSchedulerAssignments;
      };
      services.tuned = {
        inherit (cfg.gui.tuned) enable;
        package = tunedNoDesktop;
        ppdSupport = true;
        settings.profile_dirs = mkProfileDirs guiProfileScripts;
        recommend = {
          "${cfg.gui.tuned.defaultProfile}" = { };
        };
        ppdSettings = mkPpdSettings "gui";
        profiles = mapAttrs (
          name: _: tunedProfiles.vm // { script.script = "${getExe guiProfileScripts.${name}}"; }
        ) guiProfileVariants;
      };
    })

    (mkIf cfg.net.enable {
      services.tuned = {
        inherit (cfg.net.tuned) enable;
        ppdSupport = true;
        settings.sleep_interval = 60;
        settings.profile_dirs = mkProfileDirs netProfileScripts;
        recommend = {
          "${cfg.net.tuned.defaultProfile}" = { };
        };
        ppdSettings = mkPpdSettings "net";
        profiles = mapAttrs (
          _name:
          { base, ... }:
          tunedProfiles.vm
          // lib.optionalAttrs (base == "performance") {
            script.script = "${getExe netProfileScripts.net-performance}";
          }
        ) netProfileVariants;
      };

      systemd.services = mkPpdServices "net-vm" cfg.net.tuned.profileNames;
    })

    (mkIf cfg.vm.enable {
      services.tuned = {
        inherit (cfg.vm) enable;
        settings.sleep_interval = 60;
        ppdSupport = true;
        profiles = {
          vm-balanced = tunedProfiles.vm;
        };
        recommend = {
          vm-balanced = { };
        };
      };
    })
  ]);
}

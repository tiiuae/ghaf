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
  audioProfileVariants = mkProfileVariants "audio";

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
        audio-vm = "audio";
      };
    in
    mapAttrs (
      name: v:
      mkTunedScript {
        inherit name;
        start =
          # The GPU is passed through here, so its ceiling is ours to set. Only
          # on-battery powersave caps it: RP1 is 300MHz against a 1300MHz ceiling.
          ''
            pci_runtime_pm ${if v.base == "performance" then "on" else "auto"}
            gpu_max_freq ${if v.base == "powersave" && v.onBattery then "efficient" else "max"}
          ''
          + optionalString (brightness.${name} != null) (mkBrightnessScript brightness.${name})
          + optionalString useGivc (
            lib.concatStrings (
              lib.mapAttrsToList (vm: prefix: ''
                timeout 5s ${givc-cli} start service --vm "${vm}" ${prefix}-${removePrefix "gui-" name}.service &
              '') forwardTo
            )
          );
      }
    ) guiProfileVariants;

  # The NIC is passed through to this VM, so its runtime PM is ours to set.
  netProfileScripts = mapAttrs (
    name:
    { base, ... }:
    mkTunedScript {
      inherit name;
      start = ''
        pci_runtime_pm ${if base == "performance" then "on" else "auto"}
      ''
      + optionalString (base == "performance") ''
        wifi_set_pm off
      '';
      stop = optionalString (base == "performance") ''
        wifi_set_pm on
      '';
    }
  ) netProfileVariants;

  # snd_hda_intel lives here, not on the host, which blacklists the module.
  audioProfileScripts = mapAttrs (
    name:
    { base, ... }:
    mkTunedScript {
      inherit name;
      start = ''
        pci_runtime_pm ${if base == "performance" then "on" else "auto"}
      '';
    }
  ) audioProfileVariants;

  # Seconds for the [audio] plugin's snd_hda_intel power_save; 0 disables it.
  audioTimeout = {
    powersave = "5";
    balanced = "10";
    performance = "0";
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

    audio = {
      enable = mkEnableOption "Ghaf-specific power optimizations for audio-vm.";
      tuned = {
        enable = mkEnableOption "TuneD service on the audio-vm for Ghaf-specific performance profiles." // {
          default = true;
        };
        defaultProfile = mkOption {
          type = types.str;
          default = "audio-balanced";
          description = "Default TuneD profile to use on audio-vm.";
        };
        profileNames = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = lib.attrNames audioProfileVariants;
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
        # Profile changes arrive over D-Bus, so a per-second wakeup in a guest
        # is pure vmexit cost.
        settings.sleep_interval = 60;
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
          name: _: tunedProfiles.vm // { script.script = "${getExe netProfileScripts.${name}}"; }
        ) netProfileVariants;
      };

      systemd.services = mkPpdServices "net-vm" cfg.net.tuned.profileNames;
    })

    (mkIf cfg.audio.enable {
      services.tuned = {
        inherit (cfg.audio.tuned) enable;
        ppdSupport = true;
        settings.sleep_interval = 60;
        settings.profile_dirs = mkProfileDirs audioProfileScripts;
        recommend = {
          "${cfg.audio.tuned.defaultProfile}" = { };
        };
        ppdSettings = mkPpdSettings "audio";
        profiles = mapAttrs (
          name:
          { base, ... }:
          tunedProfiles.vm
          // {
            audio.timeout = audioTimeout.${base};
            script.script = "${getExe audioProfileScripts.${name}}";
          }
        ) audioProfileVariants;
      };

      systemd.services = mkPpdServices "audio-vm" cfg.audio.tuned.profileNames;
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

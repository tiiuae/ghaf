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
  inherit (lib)
    concatMapStringsSep
    getExe
    getExe'
    literalExpression
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optionalString
    replaceString
    types
    ;

  useGivc = config.ghaf.givc.enable;

  givc-cli = "${getExe' pkgs.givc-cli "givc-cli"} ${
    replaceString "/run" "/etc" config.ghaf.givc.cliArgs
  }";

  guiVmSchedulerAssignments = {
    desktop-environment = {
      nice = -9;
      ioClass = "realtime";
      ioPrio = 0;
      matchers = [
        "cosmic-comp"
      ];
    };
    waypipe = {
      nice = -12;
      ioClass = "best-effort";
      ioPrio = 1;
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
    # Session services belonging to the user
    session-services = {
      nice = 12;
      ioClass = "idle";
      matchers = [
        "include cgroup=\"/user.slice/*.service\" parent=\"systemd\""
        "include cgroup=\"/user.slice/*.session.slice/*\" parent=\"systemd\""
        "include cgroup=\"/user.slice/*app-dbus*\""
      ];
    };
    # System services belonging to root
    system-services = {
      nice = 15;
      ioClass = "idle";
      matchers = [
        "include cgroup=\"/system.slice/*\""
      ];
    };
  };

  hostSchedulerAssignments = {
    system-vms = {
      nice = -15;
      ioClass = "realtime";
      ioPrio = 0;
      matchers = [
        "include cgroup=\"/system.slice/system-sysvms.slice/*\""
      ];
    };
    app-vms = {
      nice = -10;
      ioClass = "best-effort";
      ioPrio = 2;
      matchers = [
        "include cgroup=\"/system.slice/system-appvms.slice/*\""
      ];
    };
    virtiofs = {
      nice = -7;
      ioClass = "best-effort";
      ioPrio = 4;
      matchers = [
        "virtiofsd"
      ];
    };
    # System services belonging to root
    system-services = {
      nice = 12;
      ioClass = "idle";
      matchers = [
        "include cgroup=\"/system.slice/*\""
      ];
    };
  };

  mkTunedScript =
    {
      start ? "",
      stop ? "",
    }:
    pkgs.writeShellScriptBin "tuned-script" ''
      . ${pkgs.tuned}/lib/tuned/functions

      start() {
          ${start}
          return 0
      }

      stop() {
          ${stop}
          return 0
      }

      process "$@"
    '';

  mkBrightnessScript =
    level: with pkgs; ''
      b=$(${getExe brightnessctl} get)
      m=$(${getExe brightnessctl} max)
      ((b*100/m>${toString level})) && ${getExe brightnessctl} set ${toString level}%
    '';

  # Scripts to run on gui-vm when the corresponding profile is activated or deactivated
  # For a general structure of the scripts, see:
  # https://github.com/redhat-performance/tuned/blob/master/profiles/powersave/script.sh
  guiProfileScripts = {
    gui-powersave = mkTunedScript {
      start =
        (mkBrightnessScript 40)
        + optionalString useGivc ''
          ${givc-cli} start service --vm "ghaf-host" host-powersave.service &
        '';
    };
    gui-balanced = mkTunedScript {
      start =
        (mkBrightnessScript 70)
        + optionalString useGivc ''
          ${givc-cli} start service --vm "ghaf-host" host-balanced.service &
        '';
    };
    gui-performance = mkTunedScript {
      start =
        ''''
        + optionalString useGivc ''
          ${givc-cli} start service --vm "ghaf-host" host-performance.service &
        '';
    };
    gui-powersave-battery = mkTunedScript {
      start =
        (mkBrightnessScript 25)
        + optionalString useGivc ''
          ${givc-cli} start service --vm "ghaf-host" host-powersave-battery.service &
        '';
    };

    gui-balanced-battery = mkTunedScript {
      start =
        (mkBrightnessScript 50)
        + optionalString useGivc ''
          ${givc-cli} start service --vm "ghaf-host" host-balanced-battery.service &
        '';
    };
    gui-performance-battery = mkTunedScript {
      start =
        (mkBrightnessScript 70)
        + optionalString useGivc ''
          ${givc-cli} start service --vm "ghaf-host" host-performance-battery.service &
        '';
    };
  };

  hostProfileScripts = {
    host-powersave = mkTunedScript { };
    host-balanced = mkTunedScript { };
    host-performance = mkTunedScript { };
    host-powersave-battery = mkTunedScript { };
    host-balanced-battery = mkTunedScript { };
    host-performance-battery = mkTunedScript { };
  };

  # Customized TuneD profiles based on TuneD's built-in profiles and system76-power
  tunedProfiles = {
    powersave = {
      main.summary = "Ghaf tuned profile for power saving and battery life";

      cpu = {
        governor = "schedutil|conservative|powersave";
        energy_perf_bias = "powersave|power";
        energy_performance_preference = "power";
        min_perf_pct = "0";
        max_perf_pct = "50";
        boost = "0";
      };

      acpi.platform_profile = "low-power|quiet";

      vm = {
        dirty_background_bytes = "1%";
        dirty_bytes = "5%";
        transparent_hugepages = "madvise";
      };

      audio.timeout = "5";

      scsi_host.alpm = "min_power";

      sysctl = {
        "vm.swappiness" = "30";
        "vm.laptop_mode" = "5";
        "vm.dirty_writeback_centisecs" = "1500";
        "kernel.nmi_watchdog" = "0";
      };

      video.radeon_powersave = "dpm-battery,auto";
    };

    balanced = {
      main.summary = "Ghaf tuned profile for balanced performance and power savings";

      cpu = {
        governor = "schedutil|ondemand";
        energy_perf_bias = "normal";
        energy_performance_preference = "performance";
        min_perf_pct = "0";
        max_perf_pct = "100";
        boost = "1";
        hwp_dynamic_boost = "1";
      };

      acpi.platform_profile = "balanced";

      vm = {
        dirty_background_bytes = "10%";
        dirty_bytes = "20%";
        transparent_hugepages = "madvise";
      };

      audio.timeout = "10";

      scsi_host.alpm = "medium_power";

      sysctl = {
        "vm.swappiness" = "20";
        "vm.dirty_writeback_centisecs" = "1500";
        "kernel.sched_autogroup_enabled" = "1";
        "vm.laptop_mode" = "2";
      };

      video.radeon_powersave = "dpm-balanced,auto";
    };

    performance = {
      main.summary = "Ghaf tuned profile for maximum performance";

      cpu = {
        governor = "performance";
        energy_perf_bias = "performance";
        force_latency = "cstate.id_no_zero:3|70";
        energy_performance_preference = "performance";
        min_perf_pct = "0";
        max_perf_pct = "100";
        boost = "1";
        hwp_dynamic_boost = "1";
      };

      acpi.platform_profile = "performance";

      vm = {
        dirty_bytes = "40%";
        dirty_background_bytes = "10%";
      };

      disk.readahead = ">4096";

      scsi_host.alpm = "max_performance";

      sysctl = {
        "vm.swappiness" = "10";
        "net.core.somaxconn" = ">2048";
        "vm.dirty_writeback_centisecs" = "1500";
        "vm.laptop_mode" = "0";
      };

      video.radeon_powersave = "dpm-performance,auto";
    };
  };
in
{
  options.ghaf.services.performance = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable hardware-agnostic Ghaf performance and scheduler optimizations.

        For more information, see {manpage}`tuned-main.conf(5)`, {manpage}`tuned-profiles.7`,
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

    gui = {
      enable = mkEnableOption "Ghaf-specific scheduler and power optimizations for gui-vm.";
      tuned = {
        enable = mkEnableOption "TuneD service on the gui-vm for Ghaf-specific performance profiles." // {
          default = true;
        };
        defaultProfile = mkOption {
          type = types.str;
          default = cfg.host.tuned.defaultProfile;
          description = ''
            Default TuneD profile to use on gui-vm.
            This will be propagated to the host if Ghaf's GIVC service is enabled.
          '';
        };
      };
    };

    host = {
      enable = mkEnableOption "Ghaf-specific scheduler and power optimizations for the host.";
      tuned = {
        enable = mkEnableOption "TuneD service on the host for Ghaf-specific performance profiles." // {
          default = true;
        };
        defaultProfile = mkOption {
          type = types.str;
          default =
            let
              hwType =
                if builtins.hasAttr "hardware" config.ghaf then
                  config.ghaf.hardware.definition.type or "unknown"
                else
                  "unknown";
            in
            if hwType == "desktop" then "performance" else "balanced";
          description = ''
            Default TuneD profile to use on the host.
            This will be ignored if config.ghaf.services.gui.tuned is enabled and Ghaf's GIVC service is enabled.
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = !config.hardware.system76.power-daemon.enable;
          message = "`config.ghaf.performance` conflicts with `config.hardware.system76.power-daemon.enable`.";
        }
      ];
      services.system76-scheduler = {
        enable = lib.mkForce true;
        useStockConfig = lib.mkForce false;
        exceptions = [
          "include descends=\"chrt\""
          "include descends=\"ionice\""
          "include descends=\"nice\""
          "include descends=\"taskset\""
          "include descends=\"schedtool\""
          "chrt"
          "dbus"
          "dbus-broker"
          "ionice"
          "nice"
          "rtkit-daemon"
          "systemd"
          "taskset"
          "schedtool"
        ];
      };
      systemd.services = mkIf config.ghaf.profiles.debug.enable {
        tuned = {
          serviceConfig.ExecStart = [
            ""
            ''${getExe pkgs.tuned} -P -l -D''
          ];
        };
        tuned-ppd = {
          serviceConfig.ExecStart = [
            ""
            ''${getExe' pkgs.tuned "tuned-ppd"} -l -D''
          ];
        };
      };
    }

    (mkIf cfg.gui.enable {
      services.system76-scheduler = {
        settings = {
          processScheduler = {
            pipewireBoost.enable = true;
          };
        };
        assignments = guiVmSchedulerAssignments;
      };
      services.tuned = {
        inherit (cfg.gui.tuned) enable;
        ppdSupport = true;
        settings.profile_dirs = "/etc/tuned/profiles,${
          concatMapStringsSep "," (script: "${script}") (lib.attrValues guiProfileScripts)
        }";
        ppdSettings = {
          main.default = cfg.gui.tuned.defaultProfile;
          battery = {
            power-saver = "gui-powersave-battery";
            balanced = "gui-balanced-battery";
            performance = "gui-performance-battery";
          };
          profiles = {
            power-saver = "gui-powersave";
            balanced = "gui-balanced";
            performance = "gui-performance";
          };
        };
        profiles = {
          gui-powersave = tunedProfiles.powersave // {
            script.script = "${getExe guiProfileScripts.gui-powersave}";
          };
          gui-balanced = tunedProfiles.balanced // {
            script.script = "${getExe guiProfileScripts.gui-balanced}";
          };
          gui-performance = tunedProfiles.performance // {
            script.script = "${getExe guiProfileScripts.gui-performance}";
          };
          gui-powersave-battery = tunedProfiles.powersave // {
            script.script = "${getExe guiProfileScripts.gui-powersave-battery}";
          };
          gui-balanced-battery = tunedProfiles.balanced // {
            script.script = "${getExe guiProfileScripts.gui-balanced-battery}";
          };
          gui-performance-battery = tunedProfiles.performance // {
            script.script = "${getExe guiProfileScripts.gui-performance-battery}";
          };
        };
      };
    })

    (mkIf cfg.host.enable (
      {
        services.system76-scheduler = {
          settings = {
            cfsProfiles.enable = false;
            processScheduler = {
              pipewireBoost.enable = false;
              foregroundBoost.enable = false;
            };
          };
          assignments = hostSchedulerAssignments;
        };
        services.tuned = {
          inherit (cfg.host.tuned) enable;

          settings.profile_dirs = "/etc/tuned/profiles,${
            concatMapStringsSep "," (script: "${script}") (lib.attrValues hostProfileScripts)
          }";

          ppdSettings = {
            main.default = cfg.host.tuned.defaultProfile;
            battery = {
              power-saver = "host-powersave-battery";
              balanced = "host-balanced-battery";
              performance = "host-performance-battery";
            };
            profiles = {
              power-saver = "host-powersave";
              balanced = "host-balanced";
              performance = "host-performance";
            };
          };

          profiles = {
            host-powersave = tunedProfiles.powersave // {
              script.script = "${getExe hostProfileScripts.host-powersave}";
            };
            host-balanced = tunedProfiles.balanced // {
              script.script = "${getExe hostProfileScripts.host-balanced}";
            };
            host-performance = tunedProfiles.performance // {
              script.script = "${getExe hostProfileScripts.host-performance}";
            };
            host-powersave-battery = tunedProfiles.powersave // {
              script.script = "${getExe hostProfileScripts.host-powersave-battery}";
            };
            host-balanced-battery = tunedProfiles.balanced // {
              script.script = "${getExe hostProfileScripts.host-balanced-battery}";
            };
            host-performance-battery = tunedProfiles.performance // {
              script.script = "${getExe hostProfileScripts.host-performance-battery}";
            };
          };
        };
      }
      # Service units to set Ghaf PPD profiles on the host when requested from GUI VM
      # These must be whitelisted in modules/givc/host.nix
      // {
        systemd.services =
          let
            mkPpdService = profile: {
              description = "Enable ${profile} Ghaf PPD profile on host";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = ''
                  -${getExe' pkgs.tuned "tuned-adm"} profile ${profile}
                '';
              };
            };
            hostProfiles = [
              "host-powersave"
              "host-balanced"
              "host-performance"
              "host-powersave-battery"
              "host-balanced-battery"
              "host-performance-battery"
            ];
          in
          lib.listToAttrs (map (profile: nameValuePair "${profile}" (mkPpdService profile)) hostProfiles);
      }
    ))
  ]);
}

# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  mkTunedScript,
  ...
}:
let
  cfg = config.ghaf.services.performance;
  inherit (lib)
    hasAttrByPath
    concatMapStringsSep
    getExe
    getExe'
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    types
    ;

  hostSchedulerAssignments = {
    system-vms = {
      nice = -5;
      ioClass = "best-effort";
      ioPrio = 0;
      matchers = [
        "include cgroup=\"/system.slice/system-sysvms.slice/*\""
      ];
    };
    app-vms = {
      nice = 0;
      ioClass = "best-effort";
      ioPrio = 2;
      matchers = [
        "include cgroup=\"/system.slice/system-appvms.slice/*\""
      ];
    };
    # System services belonging to root
    system-services = {
      nice = 5;
      ioClass = "best-effort";
      ioPrio = 5;
      matchers = [
        "include cgroup=\"/system.slice/*\""
        "exclude cgroup=\"/system.slice/system-sysvms.slice/*\""
        "exclude cgroup=\"/system.slice/system-appvms.slice/*\""
      ];
    };
  };

  hostProfileScripts =
    let
      # PCI devices we can adjust power management for
      pciDevices =
        if
          (hasAttrByPath [
            "hardware"
          ] config.ghaf.common)
        then
          map (device: device.path) (
            config.ghaf.common.hardware.gpus
            ++ config.ghaf.common.hardware.audio
            ++ config.ghaf.common.hardware.nics
          )
        else
          [ ];
    in
    {
      host-powersave = mkTunedScript {
        name = "host-powersave";
        start = ''
          pci_device_runtime_pm auto "${lib.concatStringsSep " " pciDevices}"
        '';
      };
      host-balanced = mkTunedScript {
        name = "host-balanced";
        start = ''
          pci_device_runtime_pm auto "${lib.concatStringsSep " " pciDevices}"
        '';
      };
      host-performance = mkTunedScript {
        name = "host-performance";
        start = ''
          pci_device_runtime_pm on "${lib.concatStringsSep " " pciDevices}"
        '';
      };
      host-powersave-battery = mkTunedScript {
        name = "host-powersave-battery";
        start = ''
          pci_device_runtime_pm auto "${lib.concatStringsSep " " pciDevices}"
        '';
      };
      host-balanced-battery = mkTunedScript {
        name = "host-balanced-battery";
        start = ''
          pci_device_runtime_pm auto "${lib.concatStringsSep " " pciDevices}"
        '';
      };
      host-performance-battery = mkTunedScript {
        name = "host-performance-battery";
        start = ''
          pci_device_runtime_pm on "${lib.concatStringsSep " " pciDevices}"
        '';
      };
    };

  # Customized TuneD profiles based on TuneD's built-in profiles and system76-power
  tunedProfiles = {
    powersave = {
      main.summary = "Ghaf TuneD profile for power saving and battery life";

      cpu = {
        governor = "powersave|conservative";
        energy_perf_bias = "powersave|power";
        energy_performance_preference = "balance_power";
        min_perf_pct = "0";
        max_perf_pct = "50";
        boost = "0";
        no_turbo = "1";
        hwp_dynamic_boost = "0";
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
    };

    balanced = {
      main.summary = "Ghaf TuneD profile for balanced performance and power savings";

      cpu = {
        governor = "powersave|ondemand|schedutil";
        energy_perf_bias = "normal";
        energy_performance_preference = "balance_performance";
        min_perf_pct = "0";
        max_perf_pct = "80";
        boost = "1";
        no_turbo = "0";
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
        "vm.laptop_mode" = "2";
      };
    };

    performance = {
      main.summary = "Ghaf TuneD profile for maximum performance";

      cpu = {
        governor = "performance";
        energy_perf_bias = "performance";
        force_latency = "cstate.id_no_zero:3|70";
        energy_performance_preference = "performance";
        min_perf_pct = "0";
        max_perf_pct = "100";
        boost = "1";
        no_turbo = "0";
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
    };
  };
in
{
  options.ghaf.services.performance = {
    host = {
      enable = mkEnableOption "Ghaf-specific scheduler and power optimizations for the host.";
      scheduler = {
        enable = mkEnableOption "system76-scheduler on host for Ghaf-specific process scheduling." // {
          default = true;
        };
      };
      tuned = {
        enable = mkEnableOption "TuneD service on the host for Ghaf-specific performance profiles." // {
          default = true;
        };
        defaultProfile = mkOption {
          type = types.str;
          # Default to performance to improve boot time
          default = "host-balanced";
          description = "Default TuneD profile to use on the host.";
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.host.enable (
      {
        services.system76-scheduler = {
          inherit (cfg.host.scheduler) enable;
          settings = {
            processScheduler = {
              refreshInterval = 60;
            };
          };
          assignments = hostSchedulerAssignments;
        };
        services.tuned = {
          inherit (cfg.host.tuned) enable;

          settings.profile_dirs = "/etc/tuned/profiles,${
            concatMapStringsSep "," (script: "${script}") (lib.attrValues hostProfileScripts)
          }";

          settings.recommend_command = false;

          ppdSettings = {
            main.default = "balanced";
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
        environment.etc."tuned/recommend.conf".text = ''
          [${cfg.host.tuned.defaultProfile}]
        '';
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

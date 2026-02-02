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
    mkForce
    mkIf
    mkMerge
    mkOption
    nameValuePair
    types
    ;
  inherit (pkgs.stdenv.hostPlatform) isx86;

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
    # System services belonging to root (host-side)
    host-system-services = {
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
        ''
        + lib.optionalString (
          cfg.host.thermalLimitMode == "ac"
        ) "timeout 5s ${getExe' pkgs.systemd "systemctl"} start thermald";
      };
      host-balanced = mkTunedScript {
        name = "host-balanced";
        start = ''
          pci_device_runtime_pm auto "${lib.concatStringsSep " " pciDevices}"
        ''
        + lib.optionalString (
          cfg.host.thermalLimitMode == "ac"
        ) "timeout 5s ${getExe' pkgs.systemd "systemctl"} start thermald";
      };
      host-performance = mkTunedScript {
        name = "host-performance";
        start = ''
          pci_device_runtime_pm on "${lib.concatStringsSep " " pciDevices}"
        ''
        + lib.optionalString (
          cfg.host.thermalLimitMode == "ac"
        ) "timeout 5s ${getExe' pkgs.systemd "systemctl"} start thermald";
      };
      host-powersave-battery = mkTunedScript {
        name = "host-powersave-battery";
        start = ''
          pci_device_runtime_pm auto "${lib.concatStringsSep " " pciDevices}"
        ''
        + lib.optionalString (
          cfg.host.thermalLimitMode == "ac"
        ) "timeout 5s ${getExe' pkgs.systemd "systemctl"} stop thermald";
      };
      host-balanced-battery = mkTunedScript {
        name = "host-balanced-battery";
        start = ''
          pci_device_runtime_pm auto "${lib.concatStringsSep " " pciDevices}"
        ''
        + lib.optionalString (
          cfg.host.thermalLimitMode == "ac"
        ) "timeout 5s ${getExe' pkgs.systemd "systemctl"} stop thermald";
      };
      host-performance-battery = mkTunedScript {
        name = "host-performance-battery";
        start = ''
          pci_device_runtime_pm on "${lib.concatStringsSep " " pciDevices}"
        ''
        + lib.optionalString (
          cfg.host.thermalLimitMode == "ac"
        ) "timeout 5s ${getExe' pkgs.systemd "systemctl"} stop thermald";
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
          default = "host-balanced";
          description = "Default TuneD profile to use on the host.";
        };
      };
      thermalLimitTemp = mkOption {
        type = types.int;
        description = ''
          CPU package temperature (°C) at which passive thermal throttling begins.

          Valid values are 60-97 °C. Lower temperatures are at or below typical CPU
          idle temps, while higher values approach the CPU's hardware thermal ceiling
          and might cause system shutdown.

          This setting is used only when
          `ghaf.services.performance.host.thermalLimitMode != "enabled"`.

          Raising this value allows the CPU to sustain higher boost clocks before
          throttling, at the cost of increased temperature, power draw, and fan noise.

          Supports Intel CPUs only.
        '';
        default = 90;
        apply =
          value: if value < 60 || value > 97 then throw "Value must be between 60 and 97 °C" else value;
      };
      thermalLimitMode = mkOption {
        type = types.enum [
          "enabled"
          "ac"
          "disabled"
        ];
        default = "ac";
        description = ''
          Controls how passive thermal limits are applied.

          `enabled` - Use the platform's built-in passive thermal limits
            (typically around 60-70 °C). Boosting and throttling behavior are
            determined entirely by firmware and ignore `thermalLimitTemp`.

          `ac` - Disable the platform's passive limits when running on AC power,
            but keep them active on battery. When passive limits are disabled,
            `thermalLimitTemp` defines the temperature at which throttling begins.
            Requires `ghaf.services.performance.host.tuned` to be enabled.

          `disabled` - Disable the platform's passive limits on both AC and
            battery. Boosting is allowed up to `thermalLimitTemp`, after which
            throttling is applied.

          Supports Intel CPUs only.
        '';
      };
    };
  };

  config = mkIf (cfg.enable && cfg.host.enable) (mkMerge [
    {
      assertions = [
        {
          assertion = (cfg.host.thermalLimitMode == "ac") -> cfg.host.tuned.enable;
          message = ''
            thermalLimitMode = "ac" requires TuneD to be enabled.
            Enable:

              ghaf.services.performance.host.tuned.enable = true;

            or choose thermalLimitMode = "enabled" or "disabled".
          '';
        }
      ];
      services.system76-scheduler = {
        inherit (cfg.host.scheduler) enable;
        settings = {
          processScheduler = {
            # Host takes precedence for refresh interval
            refreshInterval = 60;
          };
        };
        # Use mkMerge to allow merging with guest assignments
        assignments = lib.mkMerge [ hostSchedulerAssignments ];
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
      # Service units to set Ghaf PPD profiles on the host when requested from GUI VM
      # These must be whitelisted in modules/givc/host.nix
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
    # thermald is only available on x86
    (mkIf (isx86 && cfg.host.thermalLimitMode != "enabled") {
      environment.systemPackages = lib.optionals config.ghaf.profiles.debug.enable [
        # stress test and performance monitoring tool
        pkgs.s-tui
      ];
      services.thermald.enable = true;
      systemd.services.thermald =
        let
          thermaldConfig = pkgs.writeText "thermald-ghaf.xml" ''
            <?xml version="1.0"?>
            <ThermalConfiguration>
              <Platform>
                <Name>Override CPU default passive</Name>
                <ProductName>*</ProductName>
                <Preference>QUIET</Preference>
                <ThermalZones>
                  <ThermalZone>
                    <Type>x86_pkg_temp</Type>
                    <TripPoints>
                      <TripPoint>
                        <Temperature>${toString (cfg.host.thermalLimitTemp * 1000)}</Temperature>
                        <type>passive</type>
                        <SensorType>x86_pkg_temp</SensorType>
                        <ControlType>SEQUENTIAL</ControlType>
                        <CoolingDevice>
                          <type>Processor</type>
                          <SamplingPeriod>6</SamplingPeriod>
                        </CoolingDevice>
                      </TripPoint>
                    </TripPoints>
                  </ThermalZone>
                </ThermalZones>
              </Platform>
            </ThermalConfiguration>
          '';
        in
        {
          serviceConfig.ExecStart = mkForce ''
            ${getExe pkgs.thermald} \
            --no-daemon \
            --ignore-cpuid-check \
            --workaround-enabled \
            --ignore-default-control \
            --config-file ${thermaldConfig}
          '';
          after = [ "tuned.service" ];
        };
      # Throttled is a good alternative but may not
      # work with secure boot enabled
      services.throttled.enable = false;
    })
  ]);
}

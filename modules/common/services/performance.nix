# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.performance;
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  guiVmAssignments = {
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

  hostAssignments = {
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

in
{
  options.ghaf.services.performance = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable hardware-agnostic Ghaf performance and scheduler optimizations.
      '';
      example = literalExpression ''
        # In host
        config.ghaf.services.scheduler = {
          enable = true;
          host.enable = true;
        };

        # In GUI VM
        config.ghaf.services.scheduler = {
          enable = true;
          gui.enable = true;
        };
      '';
    };

    gui = {
      enable = mkEnableOption ''
        Enable Ghaf-specific scheduler optimizations for gui-vm.
      '';
    };
    host = {
      enable = mkEnableOption ''
        Enable Ghaf-specific scheduler optimizations for the host.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
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
    }
    # GUI scheduler optimizations
    (mkIf cfg.gui.enable {
      services.system76-scheduler = {
        settings = {
          processScheduler = {
            pipewireBoost.enable = true;
          };
        };
        assignments = guiVmAssignments;
      };
      services.tuned = {
        enable = true;
        ppdSupport = true;
        ppdSettings = {
          main.default = "balanced";
          battery = {
            power-saver = "laptop-battery-powersave";
            balanced = "balanced-battery";
            performance = "throughput-performance";
          };
          profiles = {
            power-saver = "laptop-ac-powersave";
            balanced = "balanced";
            performance = "virtual-guest";
          };
        };
      };
      assertions = [
        {
          assertion = !config.hardware.system76.power-daemon.enable;
          message = "`config.ghaf.performance.gui.tuned` conflicts with `config.hardware.system76.power-daemon.enable`.";
        }
      ];
    })

    # Host scheduler optimizations
    (mkIf cfg.host.enable {
      services.system76-scheduler = {
        settings = {
          cfsProfiles.enable = false;
          processScheduler = {
            pipewireBoost.enable = false;
            foregroundBoost.enable = false;
          };
        };
        assignments = hostAssignments;
      };
      services.tuned = {
        enable = true;
      };
    })
  ]);
}

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
    literalExpression
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  useGivc = config.ghaf.givc.enable;

  givc-cli = "${lib.getExe' pkgs.givc-cli "givc-cli"} ${
    lib.replaceString "/run" "/etc" config.ghaf.givc.cliArgs
  }";

  hostProfiles = [
    "host-powersave"
    "host-balanced"
    "host-performance"
    "host-powersaver-battery"
    "host-balanced-battery"
    "host-performance-battery"
  ];

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

  # Scripts to run on gui-vm when the corresponding profile is activated or deactivated
  # For a general structure of the scripts, see:
  # https://github.com/redhat-performance/tuned/blob/master/profiles/powersave/script.sh
  guiProfileScripts = {
    gui-powersave = mkTunedScript {
      start = ''
        b=$(${lib.getExe pkgs.brightnessctl} get)
        m=$(${lib.getExe pkgs.brightnessctl} max)
        ((b*100/m>40)) && ${lib.getExe pkgs.brightnessctl} set 40%
      ''
      + lib.optionalString useGivc ''
        ${givc-cli} start service --vm "ghaf-host" host-powersave.service &
      '';
    };
    gui-balanced = mkTunedScript {
      start = ''
        b=$(${lib.getExe pkgs.brightnessctl} get)
        m=$(${lib.getExe pkgs.brightnessctl} max)
        ((b*100/m>70)) && ${lib.getExe pkgs.brightnessctl} set 70%
      ''
      + lib.optionalString useGivc ''
        ${givc-cli} start service --vm "ghaf-host" host-balanced.service &
      '';
    };
    gui-performance = mkTunedScript {
      start =
        ''''
        + lib.optionalString useGivc ''
          ${givc-cli} start service --vm "ghaf-host" host-performance.service &
        '';
    };
    gui-powersave-battery = mkTunedScript {
      start = ''
        b=$(${lib.getExe pkgs.brightnessctl} get)
        m=$(${lib.getExe pkgs.brightnessctl} max)
        ((b*100/m>25)) && ${lib.getExe pkgs.brightnessctl} set 25%
      ''
      + lib.optionalString useGivc ''
        ${givc-cli} start service --vm "ghaf-host" host-powersave-battery.service &
      '';
    };

    gui-balanced-battery = mkTunedScript {
      start = ''
        b=$(${lib.getExe pkgs.brightnessctl} get)
        m=$(${lib.getExe pkgs.brightnessctl} max)
        ((b*100/m>50)) && ${lib.getExe pkgs.brightnessctl} set 50%
      ''
      + lib.optionalString useGivc ''
        ${givc-cli} start service --vm "ghaf-host" host-balanced-battery.service &
      '';
    };
    gui-performance-battery = mkTunedScript {
      start = ''

        b=$(${lib.getExe pkgs.brightnessctl} get)
        m=$(${lib.getExe pkgs.brightnessctl} max)
        ((b*100/m>70)) && ${lib.getExe pkgs.brightnessctl} set 70%
      ''
      + lib.optionalString useGivc ''
        ${givc-cli} start service --vm "ghaf-host" host-performance-battery.service &
      '';
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
      enable = mkEnableOption "Ghaf-specific scheduler and power optimizations for gui-vm.";
      tuned = {
        enable = mkEnableOption "TuneD service on the gui-vm for Ghaf-specific performance profiles." // {
          default = true;
        };
      };
    };

    host = {
      enable = mkEnableOption "Ghaf-specific scheduler and power optimizations for the host.";
      tuned = {
        enable = mkEnableOption "TuneD service on the host for Ghaf-specific performance profiles." // {
          default = true;
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
      systemd = {
        services = {
          tuned = {
            serviceConfig.ExecStart = [
              ""
              ''${lib.getExe pkgs.tuned} -P -l -D''
            ];
          };
          tuned-ppd = {
            serviceConfig.ExecStart = [
              ""
              ''${lib.getExe' pkgs.tuned "tuned-ppd"} -l -D''
            ];
          };
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
        assignments = guiVmAssignments;
      };
      services.tuned = {
        enable = true;
        ppdSupport = true;
        settings.profile_dirs = "/etc/tuned/profiles,${
          lib.concatMapStringsSep "," (script: "${script}") (lib.attrValues guiProfileScripts)
        }";
        ppdSettings = {
          main.default = "performance";
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
          gui-powersave = {
            main = {
              summary = "Tuned profile for GUI VM in powersave mode";
              include = "powersave";
            };
            acpi = {
              platform_profile = "balanced";
            };
            script.script = "${lib.getExe guiProfileScripts.gui-powersave}";
          };
          gui-balanced = {
            main = {
              summary = "Tuned profile for GUI VM in balanced mode";
              include = "virtual-guest";
            };
            acpi = {
              platform_profile = "balanced";
            };
            script.script = "${lib.getExe guiProfileScripts.gui-balanced}";
          };
          gui-performance = {
            main = {
              summary = "Tuned profile for GUI VM in performance mode";
              include = "virtual-guest";
            };
            acpi = {
              platform_profile = "balanced";
            };
            script.script = "${lib.getExe guiProfileScripts.gui-performance}";
          };
        }
        # For now battery profiles are the same as their non-battery counterparts
        // lib.listToAttrs (
          map
            (name: {
              name = "${name}";
              value = {
                main = {
                  summary = "Tuned battery profile for GUI VM in ${name} mode";
                  include = "virtual-guest";
                };
                acpi = {
                  platform_profile = "balanced";
                };
                script.script = "${lib.getExe guiProfileScripts.${name}}";
              };
            })
            [
              "gui-powersave-battery"
              "gui-balanced-battery"
              "gui-performance-battery"
            ]
        );
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
          assignments = hostAssignments;
        };
        services.tuned = {
          enable = true;

          ppdSettings = {
            main.default = "performance";
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
            host-powersave = {
              main = {
                summary = "Tuned profile for host in powersave mode";
                include = "powersave";
              };
              acpi = {
                platform_profile = "balanced";
              };
            };
            host-balanced = {
              main = {
                summary = "Tuned profile for host in balanced mode";
                include = "virtual-host";
              };
              acpi = {
                platform_profile = "balanced";
              };
            };
            host-performance = {
              main = {
                summary = "Tuned profile for host in performance mode";
                include = "virtual-host";
              };
              acpi = {
                platform_profile = "balanced";
              };
            };
          }
          # For now battery profiles are the same as their non-battery counterparts
          // lib.listToAttrs (
            map
              (name: {
                name = "${name}";
                value = {
                  main = {
                    summary = "Tuned battery profile for host in ${name} mode";
                    include = "virtual-host";
                  };
                  acpi = {
                    platform_profile = "balanced";
                  };
                };
              })
              [
                "host-powersave-battery"
                "host-balanced-battery"
                "host-performance-battery"
              ]
          );
        };
      }
      # Service units to set Ghaf PPD profiles on the host when requested from GUI VM
      // {
        systemd.services =
          let
            mkPpdService = profile: {
              description = "Enable ${profile} Ghaf PPD profile on host";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "-${lib.getExe' pkgs.tuned "tuned-adm"} profile ${profile}";
              };
            };
          in
          lib.listToAttrs (map (profile: lib.nameValuePair "${profile}" (mkPpdService profile)) hostProfiles);
      }
    ))
  ]);
}

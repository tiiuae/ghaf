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
    concatMapStringsSep
    getExe
    getExe'
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
  guiProfileScripts = {
    gui-powersave = mkTunedScript {
      name = "gui-powersave";
      start =
        (mkBrightnessScript 40)
        + optionalString useGivc ''
          timeout 5s ${givc-cli} start service --vm "ghaf-host" host-powersave.service &
          timeout 5s ${givc-cli} start service --vm "net-vm" net-powersave.service &
        '';
    };
    gui-balanced = mkTunedScript {
      name = "gui-balanced";
      start =
        (mkBrightnessScript 70)
        + optionalString useGivc ''
          timeout 5s ${givc-cli} start service --vm "ghaf-host" host-balanced.service &
          timeout 5s ${givc-cli} start service --vm "net-vm" net-balanced.service &
        '';
    };
    gui-performance = mkTunedScript {
      name = "gui-performance";
      start =
        ""
        + optionalString useGivc ''
          timeout 5s ${givc-cli} start service --vm "ghaf-host" host-performance.service &
          timeout 5s ${givc-cli} start service --vm "net-vm" net-performance.service &
        '';
    };
    gui-powersave-battery = mkTunedScript {
      name = "gui-powersave-battery";
      start =
        (mkBrightnessScript 25)
        + optionalString useGivc ''
          timeout 5s ${givc-cli} start service --vm "ghaf-host" host-powersave-battery.service &
          timeout 5s ${givc-cli} start service --vm "net-vm" net-powersave-battery.service &
        '';
    };
    gui-balanced-battery = mkTunedScript {
      name = "gui-balanced-battery";
      start =
        (mkBrightnessScript 50)
        + optionalString useGivc ''
          timeout 5s ${givc-cli} start service --vm "ghaf-host" host-balanced-battery.service &
          timeout 5s ${givc-cli} start service --vm "net-vm" net-balanced-battery.service &
        '';
    };
    gui-performance-battery = mkTunedScript {
      name = "gui-performance-battery";
      start =
        (mkBrightnessScript 70)
        + optionalString useGivc ''
          timeout 5s ${givc-cli} start service --vm "ghaf-host" host-performance-battery.service &
          timeout 5s ${givc-cli} start service --vm "net-vm" net-performance-battery.service &
        '';
    };
  };
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
          default = true;
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
        settings = {
          processScheduler = {
            refreshInterval = 30;
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
          main.default = "balanced";
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
          gui-powersave = tunedProfiles.vm // {
            script.script = "${getExe guiProfileScripts.gui-powersave}";
          };
          gui-balanced = tunedProfiles.vm // {
            script.script = "${getExe guiProfileScripts.gui-balanced}";
          };
          gui-performance = tunedProfiles.vm // {
            script.script = "${getExe guiProfileScripts.gui-performance}";
          };
          gui-powersave-battery = tunedProfiles.vm // {
            script.script = "${getExe guiProfileScripts.gui-powersave-battery}";
          };
          gui-balanced-battery = tunedProfiles.vm // {
            script.script = "${getExe guiProfileScripts.gui-balanced-battery}";
          };
          gui-performance-battery = tunedProfiles.vm // {
            script.script = "${getExe guiProfileScripts.gui-performance-battery}";
          };
        };
      };
      environment.etc."tuned/recommend.conf".text = ''
        [${cfg.gui.tuned.defaultProfile}]
      '';
    })

    (mkIf cfg.net.enable (
      {
        services.tuned = {
          inherit (cfg.net.tuned) enable;
          ppdSupport = true;
          settings.sleep_interval = 60;
          settings.profile_dirs = "/etc/tuned/profiles,${
            concatMapStringsSep "," (script: "${script}") (lib.attrValues netProfileScripts)
          }";
          ppdSettings = {
            main.default = "balanced";
            battery = {
              power-saver = "net-powersave-battery";
              balanced = "net-balanced-battery";
              performance = "net-performance-battery";
            };
            profiles = {
              power-saver = "net-powersave";
              balanced = "net-balanced";
              performance = "net-performance";
            };
          };
          profiles = {
            net-powersave = tunedProfiles.vm;
            net-balanced = tunedProfiles.vm;
            net-performance = tunedProfiles.vm // {
              script.script = "${getExe netProfileScripts.net-performance}";
            };
            net-powersave-battery = tunedProfiles.vm;
            net-balanced-battery = tunedProfiles.vm;
            net-performance-battery = tunedProfiles.vm // {
              script.script = "${getExe netProfileScripts.net-performance}";
            };
          };
        };
        environment.etc."tuned/recommend.conf".text = ''
          [${cfg.net.tuned.defaultProfile}]
        '';
      }
      # Service units to set Ghaf PPD profiles on the net-vm when requested from GUI VM
      # These must be whitelisted in modules/givc/netvm.nix
      // {
        systemd.services =
          let
            mkPpdService = profile: {
              description = "Enable ${profile} Ghaf PPD profile on net-vm";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = ''
                  -${getExe' pkgs.tuned "tuned-adm"} profile ${profile}
                '';
              };
            };
            netProfiles = [
              "net-powersave"
              "net-balanced"
              "net-performance"
              "net-powersave-battery"
              "net-balanced-battery"
              "net-performance-battery"
            ];
          in
          lib.listToAttrs (map (profile: nameValuePair "${profile}" (mkPpdService profile)) netProfiles);
      }
    ))

    (mkIf cfg.vm.enable {
      services.tuned = {
        inherit (cfg.vm) enable;
        settings.sleep_interval = 60;
        ppdSupport = true;
        profiles = {
          vm-balanced = tunedProfiles.vm;
        };
      };
      environment.etc."tuned/recommend.conf".text = ''
        [vm-balanced]
      '';
    })
  ]);
}

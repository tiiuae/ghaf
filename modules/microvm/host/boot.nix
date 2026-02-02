# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.microvm-boot;
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkMerge
    mkForce
    mkOption
    types
    filterAttrs
    removeSuffix
    optionals
    optionalAttrs
    ;
  inherit (config.ghaf.networking) hosts;
  inherit (config.ghaf.virtualization.microvm) appvm;

  # Filter system and enabled app VMs
  appVms = lib.attrNames (filterAttrs (_: vm: vm.enable) appvm.vms);
  sysVms = map (name: removeSuffix "-vm" name) (
    lib.attrNames (
      filterAttrs (_: vm: vm.evaluatedConfig.config.ghaf.type == "system-vm") config.microvm.vms
    )
  );

  # Boot priority mapping for app VMs
  bootPriorityMap = {
    low = [ "system-login.target" ]; # Start after user session is initialized
    medium = [ "system-ui.target" ]; # Start after gui-vm is ready
    high = [ "local-fs.target" ]; # Start at the same time as system VMs
  };

  # Function to evaluate boot dependency for a VM
  evalBootPriority =
    name:
    if (cfg.uiEnabled && (lib.hasAttr name appvm.vms)) then
      bootPriorityMap.${appvm.vms.${name}.bootPriority}
    else
      [ "local-fs.target" ];

  # Functions to configure systemd service dependencies
  mkServiceDependencies =
    group: service-prefix:
    lib.foldl' (
      result: name:
      result
      // {
        "${service-prefix}${name}-vm" = {
          serviceConfig.Slice = "system-${group}-${name}.slice";
          requiredBy = [ "microvms.target" ];
          requires = [ "local-fs.target" ];
          after = evalBootPriority name;
        };
      }
    ) { } (if group == "sysvms" then sysVms else appVms);

  mkAppVmDependencies = service: mkServiceDependencies "appvms" service;
  mkSysVmDependencies = service: mkServiceDependencies "sysvms" service;
  mkVmDependencies = service: (mkSysVmDependencies service) // (mkAppVmDependencies service);

  # Function to create slice hierarchy for system and app VMs
  mkSliceGroup =
    group:
    (
      {
        # Create parent slice for system and app VMs
        "system-${group}" = {
          sliceConfig = optionalAttrs cfg.uiEnabled {
            CPUAccounting = true;
            IOAccounting = true;
            CPUWeight = if (group == "sysvms") then 10000 else "idle";
            IOWeight = if (group == "sysvms") then 10000 else 1;
          };
        };
      }
      // (lib.foldl' (result: name: result // { "system-${group}-${name}" = { }; }) { } (
        if group == "sysvms" then sysVms else appVms
      ))
    );
  mkSliceGroups = (mkSliceGroup "sysvms") // (mkSliceGroup "appvms");

  # Reset resource constraints for system and app VMs
  reset-resources = pkgs.writeShellApplication {
    name = "reset-resources";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      systemctl set-property --runtime system-sysvms.slice CPUWeight= IOWeight=
      systemctl set-property --runtime system-appvms.slice CPUWeight= IOWeight=
      systemctl daemon-reload
    '';
  };

  wait-for-session = pkgs.writeShellApplication {
    name = "wait-for-session";
    runtimeInputs = [
      pkgs.systemd
      pkgs.jq
    ];
    text = ''
      echo "Waiting for user to login..."
      USER_ID=1
      while [ "$USER_ID" -lt 1000 ]; do
        tmp_id=$(loginctl list-sessions --json=short | jq -e '.[] | select(.seat != null) | .uid') || true
        [[ "$tmp_id" =~ ^[0-9]+$ ]] && USER_ID="$tmp_id" || USER_ID=1
        sleep 1
      done
      echo "User with ID=$USER_ID is now active"

      echo "Waiting for user-session to be running..."
      state="inactive"
      while [[ "$state" != "active" ]]; do
        state=$(systemctl --user is-active session.slice --machine="$USER_ID"@.host) || true
        sleep 1
      done
      echo "User-session is active"
    '';
  };
in
{
  options.ghaf.microvm-boot = {
    enable = mkEnableOption "ghaf-specific microvm boot order";
    debug = mkEnableOption "resource tracing of the ghaf-specific microvm boot order";
    uiEnabled = mkOption {
      type = types.bool;
      default = config.ghaf.virtualization.microvm.guivm.enable && config.ghaf.givc.enable;
      description = "Enable microvm boot order for GUI targets";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {

      # Systemd boot targets
      systemd.targets = {
        # Override microvm.nix's default target (default is VMs with autostart)
        microvms = {
          wants = mkForce (map (name: "microvm@${name}.service") (lib.attrNames config.microvm.vms));
        };
      }
      // optionalAttrs cfg.uiEnabled {
        system-ui = {
          description = "System UI target";
          wantedBy = [ "microvms.target" ];
          requires = [ "wait-for-ui.service" ];
          after = [ "wait-for-ui.service" ];
        };
        system-login = {
          description = "System Login target";
          wantedBy = [ "microvms.target" ];
          requires = [ "wait-for-login.service" ];
          after = [ "wait-for-login.service" ];
        };
      };

      # Slice groups for system- and app VMs
      systemd.slices = mkSliceGroups;

      # Systemd service dependencies
      systemd.services =
        mkVmDependencies "microvm@"
        // mkVmDependencies "microvm-virtiofsd@"
        // mkAppVmDependencies "vsockproxy-"
        // mkAppVmDependencies "ghaf-mem-manager-"
        // optionalAttrs cfg.uiEnabled {

          # Wait for gui-vm to reach multi-user.target. Times out after 60 seconds
          wait-for-ui = {
            description = "Wait for GuiVM startup";
            after = [ "givc-key-setup.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = ''
                ${pkgs.wait-for-unit}/bin/wait-for-unit \
                ${hosts.admin-vm.ipv4} 9001 \
                gui-vm \
                greetd.service \
                60
              '';
              RemainAfterExit = true;
            };
          };

          # Service to wait for user login to gui-vm. Resets boot resource constraints
          # after user has logged in and ghaf-session is active. Times out after 120 seconds
          wait-for-login = {
            description = "Wait for user login to gui-vm";
            after = [
              "givc-key-setup.service"
              "system-ui.target"
            ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = ''
                ${pkgs.wait-for-unit}/bin/wait-for-unit \
                ${hosts.admin-vm.ipv4} 9001 \
                gui-vm \
                user-login.service \
                120
              '';
              ExecStartPost = "${reset-resources}/bin/reset-resources";
              RemainAfterExit = true;
            };
          };
        };

      ghaf.virtualization.microvm.extensions.guivm = optionals cfg.uiEnabled [
        {
          # Allow systemd units to be monitored via givc
          givc.sysvm.services = [
            "greetd.service"
            "user-login.service"
          ];

          # Wait until user logs in and ghaf-session is active
          systemd.services.user-login = {
            description = "Wait for ghaf-session to be active";
            wantedBy = [ "multi-user.target" ];
            after = [ "greetd.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStartPre = "${getExe wait-for-session}";
              ExecStart = "/bin/sh -c exit"; # no-op
              RemainAfterExit = true;
            };
          };
        }
      ];
    })

    # Enable systemd-bootchart if debug is enabled
    (mkIf cfg.debug {
      systemd.services.systemd-bootchart = {
        description = "Trace microvm boot with systemd-bootchart";
        wantedBy = [ "local-fs.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.systemd-bootchart}/lib/systemd/systemd-bootchart -r -n 1500";
        };
      };
    })
  ];
}

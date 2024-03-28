# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
with builtins; let
  configHost = config;
  cfg = config.ghaf.virtualization.microvm.appvm;
  makeVm = {
    vm,
    index,
  }: let
    vmName = "${vm.name}-vm";
    cid =
      if vm.cid > 0
      then vm.cid
      else cfg.vsockBaseCID + index;
    appvmConfiguration = {
      imports = [
        (import ./common/vm-networking.nix {
          inherit vmName;
          inherit (vm) macAddress;
        })
        ({
          lib,
          config,
          pkgs,
          ...
        }: let
          waypipeBorder =
            if vm.borderColor != null
            then "--border \"${vm.borderColor}\""
            else "";
          runWaypipe = with pkgs;
            writeScriptBin "run-waypipe" ''
              #!${runtimeShell} -e
              ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString configHost.ghaf.virtualization.microvm.guivm.waypipePort} ${waypipeBorder} server $@
            '';
        in {
          ghaf = {
            users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;

            development = {
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
            };
            systemd = {
              enable = true;
              withName = "appvm-systemd";
              withNss = true;
              withResolved = true;
              withPolkit = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
            };
          };

          # SSH is very picky about the file permissions and ownership and will
          # accept neither direct path inside /nix/store or symlink that points
          # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
          # setting mode), instead of symlinking it.
          environment.etc."ssh/get-auth-keys" = {
            source = let
              script = pkgs.writeShellScriptBin "get-auth-keys" ''
                [[ "$1" != "ghaf" ]] && exit 0
                ${pkgs.coreutils}/bin/cat /run/waypipe-ssh-public-key/id_ed25519.pub
              '';
            in "${script}/bin/get-auth-keys";
            mode = "0555";
          };
          services.openssh = {
            authorizedKeysCommand = "/etc/ssh/get-auth-keys";
            authorizedKeysCommandUser = "nobody";
          };

          system.stateVersion = lib.trivial.release;

          nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

          environment.systemPackages = [
            pkgs.waypipe
            runWaypipe
          ];

          microvm = {
            optimize.enable = false;
            mem = vm.ramMb;
            vcpu = vm.cores;
            hypervisor = "qemu";
            shares = [
              {
                tag = "waypipe-ssh-public-key";
                source = "/run/waypipe-ssh-public-key";
                mountPoint = "/run/waypipe-ssh-public-key";
              }
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
              }
            ];
            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

            qemu.extraArgs = [
              "-M"
              "q35,accel=kvm:tcg,mem-merge=on,sata=off"
              "-device"
              "vhost-vsock-pci,guest-cid=${toString cid}"
            ];
          };
          fileSystems."/run/waypipe-ssh-public-key".options = ["ro"];

          imports = [../../../common];
        })
      ];
    };
  in {
    autostart = true;
    config = appvmConfiguration // {imports = appvmConfiguration.imports ++ cfg.extraModules ++ vm.extraModules ++ [{environment.systemPackages = vm.packages;}];};
  };

  formatHexOctet = n:
    assert 0 <= n && n < 256; let
      n' = lib.trivial.toHexString n;
      # Pad with zero.
      # Length is always 1 or 2, because of assertion.
      prefix =
        if stringLength n' == 1
        then "0"
        else "";
    in
      prefix + n';

  allocateMacsUnsafe = vms: let
    takenMacAddresses = filter (macAddress: macAddress != null) (map (vm: vm.macAddress) vms);

    appvmMacAddressSpace = map (i: "02:00:00:03:${formatHexOctet i}:01") (lib.lists.range 0 255);

    availableMacAddresses = lib.lists.subtractLists takenMacAddresses appvmMacAddressSpace;
  in
    (foldl' ({
        availableMacAddresses,
        vms,
      }: vm: let
        allocated =
          if vm.macAddress == null
          then {
            availableMacAddresses' = tail availableMacAddresses;
            macAddress' = head availableMacAddresses;
          }
          else {
            availableMacAddresses' = availableMacAddresses;
            macAddress' = vm.macAddress;
          };
        inherit (allocated) availableMacAddresses' macAddress';
        vm' =
          vm
          // {
            macAddress = macAddress';
          };
      in {
        availableMacAddresses = availableMacAddresses';
        vms = vms ++ [vm'];
      }) {
        inherit availableMacAddresses;
        vms = [];
      }
      vms)
    .vms;

  allocateMacs = vms: let
    vmsWithMacs = allocateMacsUnsafe vms;

    macCollisions = lib.attrsets.filterAttrs (_address: vms: length vms > 1) (groupBy (vm: vm.macAddress) vmsWithMacs);
    macCollisions' = mapAttrs (_address: vms: map (vm: vm.name) vms) macCollisions;
    macCollisionsMsg = "Found following collisions among app virtual machines mac addresses: ${toJSON macCollisions'}";
  in
    assert lib.asserts.assertMsg (length (attrNames macCollisions) == 0) macCollisionsMsg; vmsWithMacs;
in {
  options.ghaf.virtualization.microvm.appvm = with lib; {
    enable = lib.mkEnableOption "appvm";
    vms = with types;
      mkOption {
        description = ''
          List of AppVMs to be created
        '';
        type = lib.types.listOf (submodule {
          options = {
            name = mkOption {
              description = ''
                Name of the AppVM
              '';
              type = str;
            };
            packages = mkOption {
              description = ''
                Packages that are included into the AppVM
              '';
              type = types.listOf package;
              default = [];
            };
            macAddress = mkOption {
              description = ''
                AppVM's network interface MAC address
              '';
              type = nullOr str;
              default = null;
            };
            ramMb = mkOption {
              description = ''
                Amount of RAM for this AppVM
              '';
              type = int;
            };
            cores = mkOption {
              description = ''
                Amount of processor cores for this AppVM
              '';
              type = int;
            };
            extraModules = mkOption {
              description = ''
                List of additional modules to be imported and evaluated as part of
                appvm's NixOS configuration.
              '';
              default = [];
            };
            cid = mkOption {
              description = ''
                VSOCK context identifier (CID) for the AppVM
                Default value 0 means auto-assign using vsockBaseCID and AppVM index
              '';
              type = int;
              default = 0;
            };
            borderColor = mkOption {
              description = ''
                Border color of the AppVM window
              '';
              type = nullOr str;
              default = null;
            };
          };
        });
        default = [];
      };

    extraModules = mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        appvm's NixOS configuration.
      '';
      default = [];
    };

    # Base VSOCK CID which is used for auto assigning CIDs for all AppVMs
    # For example, when it's set to 100, AppVMs will get 100, 101, 102, etc.
    # It is also possible to override the auto assinged CID using the vms.cid option
    vsockBaseCID = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = ''
        Context Identifier (CID) of the AppVM VSOCK
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms = let
      vms = lib.imap0 (index: vm: {"${vm.name}-vm" = makeVm {inherit index vm;};}) (allocateMacs cfg.vms);
    in
      lib.foldr lib.recursiveUpdate {} vms;
  };
}

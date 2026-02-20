# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# Copyright 2020-2023 Pacman99 and the Digga Contributors
#
# SPDX-License-Identifier: MIT
# FlattenTree and rakeLeaves originate from
# https://github.com/divnix/digga
_: lib: prev:
let
  # Import launcher utilities
  launcherLib = import ./launcher.nix { inherit lib; };
  # Import global config types and utilities
  globalConfigLib = import ./global-config.nix { inherit lib; };
  # Note: VM base modules are in modules/microvm/sysvms/*-base.nix
  # and exported via nixosModules (e.g., guivm-base, netvm-base, etc.)
  # Profiles (laptop-x86, orin) create *Base options using these modules.
in
{
  /*
       *
       Filters Nix packages based on the target system platform.
       Returns a filtered attribute set of Nix packages compatible with the target system.

    # Example

    ```
    lib.platformPkgs "x86_64-linux" {
       hello-compatible = pkgs.hello.overrideAttrs (old: { meta.platforms = ["x86_64-linux"]; });
       hello-inccompatible = pkgs.hello.overrideAttrs (old: { meta.platforms = ["aarch-linux"]; });
    }
    => { hello-compatible = «derivation /nix/store/g2mxdrkwr1hck4y5479dww7m56d1x81v-hello-2.12.1.drv»; }
    ```

    # Type

    ```
    filterAttrs :: String -> AttrSet -> AttrSet
    ```

    # Arguments

    - [system] Target system platform (e.g., "x86_64-linux").
    - [pkgsSet] a set of Nix packages.
  */
  # TODO should this be replaced with flake-parts pkgs-by-name
  platformPkgs =
    system:
    lib.filterAttrs (
      _: value:
      let
        platforms =
          lib.attrByPath
            [
              "meta"
              "platforms"
            ]
            [ ]
            value;
      in
      lib.elem system platforms
    );

  types = prev.types // {
    networking = lib.types.submodule {
      # keep-sorted start skip_lines=1 block=yes newline_separated=yes
      options = {
        cid = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = ''
            Vsock CID (Context IDentifier) as integer:
            - VMADDR_CID_HYPERVISOR (0) is reserved for services built into the hypervisor
            - VMADDR_CID_LOCAL (1) is the well-known address for local communication (loopback)
            - VMADDR_CID_HOST (2) is the well-known address of the host
          '';
        };

        interfaceName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Name of the network interface.";
        };

        ipv4 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "IPv4 address as string.";
          default = null;
        };

        ipv4SubnetPrefixLength = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "The IPv4 subnet prefix length (e.g. 24 for 255.255.255.0)";
          example = 24;
        };

        ipv6 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "IPv6 address as string.";
          default = null;
        };

        mac = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "MAC address as string.";
          default = null;
        };

        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "Host name as string.";
          default = null;
        };

      };
      # keep-sorted end
    };
    policy = lib.types.submodule {
      options = {
        factory = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Initial policy file path or nix store path.";
        };
        dest = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          description = "Destination file path (must not be null).";
          default = null;
        };
        script = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Script to execute after a policy update.";
        };
        depends = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Services to restart when this policy file changes.";
        };
        updater = {
          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "URL to pull updates for this specific policy.";
          };
          poll_interval_secs = lib.mkOption {
            type = lib.types.int;
            default = 300;
            description = "Polling interval in seconds.";
          };
        };
      };
    };

    # Global configuration type for ghaf.global-config
    globalConfig = globalConfigLib.globalConfigType;

    ghafApplication = lib.types.submodule {
      # keep-sorted start skip_lines=1 block=yes
      options = {
        categories = lib.mkOption {
          description = "The `Categories` of the desktop entry; see https://specifications.freedesktop.org/menu-spec/1.0/category-registry.html for possible values";
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        description = lib.mkOption {
          type = lib.types.str;
          description = "The `Comment` of the desktop entry";
        };
        desktopName = lib.mkOption {
          type = lib.types.str;
          description = "The `Name` of the desktop entry";
          default = "";
        };
        exec = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = ''
            The `Exec` of the desktop entry.
            If `vm` is set, this command will be executed in the target VM.
          '';
          default = null;
        };
        extraModules = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          description = "Additional modules required for the application";
          default = [ ];
        };
        genericName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "The `GenericName` of the desktop entry";
          default = null;
        };
        givcArgs = lib.mkOption {
          description = "GIVC arguments for the application";
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        icon = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "The `Icon` of the desktop entry";
          default = null;
        };
        name = lib.mkOption {
          type = lib.types.str;
          description = "The name of the desktop file (excluding the .desktop or .directory file extensions)";
        };
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          description = "Packages required for this application";
          default = [ ];
        };
        startupWMClass = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "The `StartupWMClass` of the desktop entry";
          default = null;
        };
        vm = lib.mkOption {
          description = "VM name in case this launches an isolated application.";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
      # keep-sorted end
    };
  };

  # Launcher utilities (remove desktop entries from packages)
  inherit (launcherLib) rmDesktopEntry rmDesktopEntries;

  # Global configuration utilities under ghaf namespace
  ghaf = {
    inherit (globalConfigLib)
      profiles
      mkGlobalConfig
      # VM composition utilities organized under lib.ghaf.vm.*
      vm
      # Feature assignment utilities under lib.ghaf.features.*
      features
      ;
  };
}

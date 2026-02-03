# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# Copyright 2020-2023 Pacman99 and the Digga Contributors
#
# SPDX-License-Identifier: MIT
# FlattenTree and rakeLeaves originate from
# https://github.com/divnix/digga
_: lib: prev:
let
  # Import launcher utilities
  launcherLib = import ./launcher.nix { };
  # Import global config types and utilities
  globalConfigLib = import ./global-config.nix { inherit lib; };
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
      options = {
        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "Host name as string.";
          default = null;
        };
        mac = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "MAC address as string.";
          default = null;
        };
        ipv4 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "IPv4 address as string.";
          default = null;
        };
        ipv6 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "IPv6 address as string.";
          default = null;
        };
        ipv4SubnetPrefixLength = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "The IPv4 subnet prefix length (e.g. 24 for 255.255.255.0)";
          example = 24;
        };
        interfaceName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Name of the network interface.";
        };
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
      };
    };

    # Global configuration type for ghaf.global-config
    globalConfig = globalConfigLib.globalConfigType;
  };

  # Launcher utilities
  inherit (launcherLib) rmDesktopEntries;

  # Global configuration utilities under ghaf namespace
  ghaf = {
    inherit (globalConfigLib) profiles mkVmSpecialArgs mkGlobalConfig;
  };
}

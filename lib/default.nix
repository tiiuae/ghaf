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
          description = "Services to restart after the policy update and after successful execution of the policy script if it is defined.";
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
        noDisplay = lib.mkOption {
          type = lib.types.bool;
          description = "The `NoDisplay` field of the desktop entry";
          default = false;
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

  # Data channel for virtiofs file sharing
  dataChannel = lib.types.submodule {
    options = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "fallback"
          "untrusted"
          "trusted"
        ];
        description = ''
          Channel operation mode:
          - `fallback`: Plain virtiofs share - all VMs access the same directory directly (no isolation, not recommended)
          - `untrusted`: Per-writer isolation with scanning enabled by default
          - `trusted`: Per-writer isolation with scanning disabled by default
        '';
      };

      readWrite = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              mountPoint = lib.mkOption {
                type = lib.types.path;
                description = "Mount path inside VM";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = "root";
                description = "Owner user for the mount point directory";
              };
              group = lib.mkOption {
                type = lib.types.str;
                default = "root";
                description = "Owner group for the mount point directory";
              };
              mode = lib.mkOption {
                type = lib.types.str;
                default = "0755";
                description = "Permissions mode for the mount point directory";
              };
              notify = lib.mkEnableOption "vsock notifications when files change in this channel";
            };
          }
        );
        default = { };
        description = "Read-write participants. Content is synced bi-directionally between all readWrite participants.";
      };

      readOnly = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              mountPoint = lib.mkOption {
                type = lib.types.path;
                description = "Mount path inside VM or host bind mount target";
              };
              notify = lib.mkEnableOption "vsock notifications when files change in this channel";
            };
          }
        );
        default = { };
        description = "Read-only participants. Can only read the aggregated export from all writers.";
      };

      writeOnly = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              mountPoint = lib.mkOption {
                type = lib.types.path;
                description = "Mount path inside VM";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = "root";
                description = "Owner user for the mount point directory";
              };
              group = lib.mkOption {
                type = lib.types.str;
                default = "root";
                description = "Owner group for the mount point directory";
              };
              mode = lib.mkOption {
                type = lib.types.str;
                default = "0755";
                description = "Permissions mode for the mount point directory";
              };
            };
          }
        );
        default = { };
        description = ''
          Write-only participants (diode mode). Can write files but content from other
          participants is not propagated back to them. Can read/write own data, but
          cannot modify existing propagated files.

          Use cases:
          - Public keys shared during secure initialization that should not be changed
          - Less trusted VMs that need write access but should not see other content
        '';
      };

      scanning = {
        enable = lib.mkEnableOption "scanning for this channel" // {
          default = true;
        };
        permissive = lib.mkEnableOption "permissive mode - this will treat scanning errors as clean files";
        infectedAction = lib.mkOption {
          type = lib.types.enum [
            "log"
            "quarantine"
            "delete"
          ];
          default = "quarantine";
          description = ''
            Action to take when an infected file is detected:
            - `log`: Log the infection but leave the file in place
            - `quarantine`: Move the file to quarantine directory
            - `delete`: Delete the infected file
          '';
        };
        ignoreFilePatterns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            ".crdownload"
            ".part"
            ".tmp"
            "~$"
          ];
          description = "File name suffix patterns to ignore. Matching files are not scanned or propagated, and remain only in the original location.";
        };
        ignorePathPatterns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            ".Trash-"
          ];
          description = "Path substring patterns to ignore. Matching files are not scanned or propagated, and remain only in the original location.";
        };
      };

      debounceMs = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Debounce time in milliseconds for file `close-write` events to avoid multiple scans for rapid changes.";
      };

      userNotify = {
        enable = lib.mkEnableOption "desktop notifications for scan events" // {
          default = true;
        };
        socket = lib.mkOption {
          type = lib.types.str;
          default = "/run/clamav/notify.sock";
          description = "Unix socket path for sending user notifications";
        };
      };

      guestNotify = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 3401;
          description = "Vsock port for notifications (must match virtiofs-notify service on guests)";
        };
      };
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

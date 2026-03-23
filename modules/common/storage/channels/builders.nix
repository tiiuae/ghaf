# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Channel builder functions
#
# These functions construct channel definition attrsets.
# Used by both host.nix and vm.nix.
#
{ lib }:
{
  # Filter appvms that have XDG features enabled
  filterXdgAppvms =
    appvms:
    lib.filterAttrs (
      _: vm:
      (vm.xdgitems.enable or false) || (vm.xdghandlers.pdf or false) || (vm.xdghandlers.image or false)
    ) appvms;

  # Filter appvms that have desktop share enabled
  filterDesktopShareAppvms = appvms: lib.filterAttrs (_: vm: vm.desktopShare.enable or false) appvms;

  # Build XDG channel definition
  #
  # Arguments:
  #   writers: attrset of appvm names (without -vm suffix) that are writers
  #   graphicsTarget: "gui-vm" or "host" or null
  #   mountPoint: path where channel is mounted
  #   selfVm: optional - if set, only include this VM (for appvm self-participation)
  mkXdgChannel =
    {
      writers ? { },
      graphicsTarget ? null,
      mountPoint,
      selfVm ? null,
    }:
    {
      mode = "untrusted";
      debounceMs = 10;
      readWrite =
        # Include all writers (host/sysvm case)
        lib.mapAttrs' (name: _: {
          name = "${name}-vm";
          value = {
            inherit mountPoint;
            user = "root";
            group = "users";
            mode = "0770";
          };
        }) writers
        # Include self (appvm case)
        // lib.optionalAttrs (selfVm != null) {
          ${selfVm} = {
            inherit mountPoint;
            user = "root";
            group = "users";
            mode = "0770";
          };
        }
        # Include graphics target
        // lib.optionalAttrs (graphicsTarget != null) {
          ${graphicsTarget} = {
            inherit mountPoint;
            user = "root";
            group = "users";
            mode = "0770";
          };
        };
    };

  # Build identity channel definition (host writes, VMs read)
  #
  # Arguments:
  #   writer: participant name that has write access (e.g., hostName), or null
  #   readers: list of participant names that should read (e.g., ["admin-vm", "gui-vm"])
  #   mountPoint: path where channel is mounted
  mkIdentityChannel =
    {
      writer ? null,
      readers ? [ ],
      mountPoint,
    }:
    {
      mode = "trusted";
      readWrite = lib.optionalAttrs (writer != null) {
        ${writer} = {
          inherit mountPoint;
          user = "root";
          group = "root";
          mode = "0755";
        };
      };
      readOnly = lib.listToAttrs (
        map (name: {
          inherit name;
          value.mountPoint = mountPoint;
        }) readers
      );
      userNotify.enable = false;
    };

  # Build public keys channel definition (one rw participant, others write-only)
  #
  # Arguments:
  #   rwParticipant: participant name with read-write access (e.g., "admin-vm"), or null
  #   woParticipants: attrset of participant names for write-only access (e.g., { gui-vm = true; host = true; })
  #   mountPoint: path where channel is mounted
  mkPublicKeysChannel =
    {
      rwParticipant ? null,
      woParticipants ? { },
      mountPoint,
    }:
    {
      mode = "untrusted";
      readWrite = lib.optionalAttrs (rwParticipant != null) {
        ${rwParticipant} = {
          inherit mountPoint;
          user = "root";
          group = "root";
          mode = "0755";
        };
      };
      writeOnly = lib.mapAttrs (_: _: { inherit mountPoint; }) woParticipants;
      # Use permissive scanning as the channel data is initialized on first boot
      # where scanning is not available yet. Scanning will be done once available
      scanning.permissive = true;
      userNotify.enable = false;
    };

  # Build desktop share channel for a single appvm
  #
  # Arguments:
  #   appvmName: name without -vm suffix (e.g., "chrome")
  #   graphicsTarget: "gui-vm" or "host"
  #   guiMountPoint: base path for shares on GUI side (e.g., "/Shares")
  #   appvmMountPoint: base path for shares on AppVM side (e.g., "/home/appuser/Shares")
  #   selfOnly: if true, only include the appvm side (for appvm self-participation)
  mkDesktopShareChannel =
    {
      appvmName,
      graphicsTarget ? null,
      guiMountPoint,
      appvmMountPoint,
      selfOnly ? false,
    }:
    {
      mode = "untrusted";
      readWrite =
        lib.optionalAttrs (graphicsTarget != null && !selfOnly) {
          ${graphicsTarget} = {
            mountPoint = "${guiMountPoint}/Unsafe-${appvmName}";
            notify = true;
            user = "root";
            group = "users";
            mode = "0770";
          };
        }
        // {
          "${appvmName}-vm" = {
            mountPoint = "${appvmMountPoint}/Desktop Share";
            notify = true;
            user = "root";
            group = "users";
            mode = "0770";
          };
        };
    };
}

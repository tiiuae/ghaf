# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-side channel configuration module
#
# Handles both SysVMs (gui-vm, admin-vm, etc.) and AppVMs:
# - SysVMs: Read from hostConfig.appvms (passed via specialArgs)
# - AppVMs: Read from vmDef (self-only participation)
#
{
  config,
  options,
  lib,
  hostConfig ? null,
  ...
}:
let
  inherit (lib)
    mkIf
    mapAttrs'
    optionalAttrs
    ;

  cfg = config.ghaf.storage.channels;

  # Environment detection
  isHost = options.ghaf.virtualization ? microvm-host;
  vmName = config.networking.hostName;

  # AppVM detection - appvms have vmDef with feature flags
  vmDef = config.ghaf.appvm.vmDef or null;
  isAppVm = vmDef != null;
  isSysVm = !isAppVm && hostConfig != null;
  isGuiVm = vmName == "gui-vm";
  isAdminVm = vmName == "admin-vm";

  # Import builders
  builders = import ./builders.nix { inherit lib; };

  # Data sources - SysVMs read from hostConfig, AppVMs use empty (to avoid cycle)
  enabledAppvms = if isSysVm then (hostConfig.appvms or { }) else { };

  # Graphics target
  graphicsTarget = if isGuiVm then "gui-vm" else null;
  hasGraphicsTarget = graphicsTarget != null;

  # Feature flag filtering
  xdgAppvms = builders.filterXdgAppvms enabledAppvms;
  desktopShareAppvms = builders.filterDesktopShareAppvms enabledAppvms;

  # AppVM feature detection
  appvmHasXdg =
    (vmDef.xdgitems.enable or false)
    || (vmDef.xdghandlers.pdf or false)
    || (vmDef.xdghandlers.image or false);
  appvmHasDesktopShare = vmDef.desktopShare.enable or false;
  appvmName = if isAppVm then lib.removeSuffix "-vm" vmName else null;

  # Channel definitions for SysVMs
  sysvmXdgChannel = builders.mkXdgChannel {
    writers = xdgAppvms;
    inherit graphicsTarget;
    inherit (cfg.xdg) mountPoint;
  };

  sysvmIdentityChannel = builders.mkIdentityChannel {
    readers = [ vmName ];
    inherit (cfg.ghafIdentity) mountPoint;
  };

  sysvmPublicKeysChannel = builders.mkPublicKeysChannel {
    rwParticipant = if isAdminVm then "admin-vm" else null;
    woParticipants = if isAdminVm then { } else { ${vmName} = true; };
    inherit (cfg.ghafPublicKeys) mountPoint;
  };

  sysvmDesktopShareChannels = mapAttrs' (name: _: {
    name = "gui-${name}-share";
    value = builders.mkDesktopShareChannel {
      appvmName = name;
      inherit graphicsTarget;
      inherit (cfg.desktopShares) guiMountPoint appvmMountPoint;
    };
  }) desktopShareAppvms;

  # Channel definitions for AppVMs (self-only participation)
  appvmXdgChannel = builders.mkXdgChannel {
    selfVm = vmName;
    inherit (cfg.xdg) mountPoint;
  };

  appvmIdentityChannel = builders.mkIdentityChannel {
    readers = [ vmName ];
    inherit (cfg.ghafIdentity) mountPoint;
  };

  appvmPublicKeysChannel = builders.mkPublicKeysChannel {
    woParticipants = {
      ${vmName} = true;
    };
    inherit (cfg.ghafPublicKeys) mountPoint;
  };

  appvmDesktopShareChannel = builders.mkDesktopShareChannel {
    inherit appvmName;
    inherit (cfg.desktopShares) guiMountPoint appvmMountPoint;
    selfOnly = true;
  };

  # Combined channels based on VM type
  sysvmChannels =
    optionalAttrs (cfg.xdg.enable && (xdgAppvms != { } || hasGraphicsTarget)) { xdg = sysvmXdgChannel; }
    // optionalAttrs cfg.ghafIdentity.enable { ghaf-identity = sysvmIdentityChannel; }
    // optionalAttrs cfg.ghafPublicKeys.enable { ghaf-keys = sysvmPublicKeysChannel; }
    // optionalAttrs (
      cfg.desktopShares.enable && hasGraphicsTarget && desktopShareAppvms != { }
    ) sysvmDesktopShareChannels
    // optionalAttrs (cfg.extraChannels != { }) cfg.extraChannels;

  appvmChannels =
    optionalAttrs (cfg.xdg.enable && appvmHasXdg) { xdg = appvmXdgChannel; }
    // optionalAttrs cfg.ghafIdentity.enable { ghaf-identity = appvmIdentityChannel; }
    // optionalAttrs cfg.ghafPublicKeys.enable { ghaf-keys = appvmPublicKeysChannel; }
    // optionalAttrs (cfg.desktopShares.enable && appvmHasDesktopShare) {
      "gui-${appvmName}-share" = appvmDesktopShareChannel;
    }
    // optionalAttrs (cfg.extraChannels != { }) cfg.extraChannels;

  channels = if isAppVm then appvmChannels else sysvmChannels;

  # Extract all mount points where this VM participates (for ClamAV exclusion)
  excludeDirectories = lib.pipe (lib.attrValues channels) [
    (lib.concatMap (
      ch:
      map (m: ch.${m}.${vmName}.mountPoint or null) [
        "readWrite"
        "readOnly"
        "writeOnly"
      ]
    ))
    (lib.filter (p: p != null))
  ];
in
{
  config = mkIf (cfg.enable && !isHost) {
    ghaf.storage.shared-directories = {
      inherit (cfg) enable debug;
      inherit channels;
    };

    # Auto-exclude channel mount points from local ClamAV on-modify scanning
    # to avoid double-scanning (host virtiofs-gate handles the scan logic)
    ghaf.security.clamav.scan.on-modify = {
      inherit excludeDirectories;
    };
  };
}

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pure builder functions for shared directories configuration
#
{ lib }:
rec {
  # ═══════════════════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════════════════

  # Path helpers
  channelBase = baseDir: channel: "${baseDir}/${channel}";
  writerSharePath =
    baseDir: channel: name:
    "${channelBase baseDir channel}/share/${name}";
  exportPath = baseDir: channel: "${channelBase baseDir channel}/export";
  exportRoPath = baseDir: channel: "${channelBase baseDir channel}/export-ro";

  # Channel config helpers
  isFallbackMode = channelCfg: channelCfg.mode == "fallback";
  allWriters = channelCfg: channelCfg.readWrite // channelCfg.writeOnly;
  isWriter = channelCfg: name: (allWriters channelCfg) ? ${name};
  isReader = channelCfg: name: channelCfg.readOnly ? ${name};
  isInChannel = channelCfg: name: (isWriter channelCfg name) || (isReader channelCfg name);
  getVmConfig = channelCfg: name: (allWriters channelCfg).${name} or channelCfg.readOnly.${name};

  # ═══════════════════════════════════════════════════════════════════════════
  # VM Configuration Builders
  # ═══════════════════════════════════════════════════════════════════════════

  # Build VM share configuration for a single channel
  # Returns: { tmpfileRule, share, filesystem }
  mkVmShareConfig =
    {
      channel,
      channelCfg,
      vmName,
      baseDirectory,
    }:
    let
      simple = isFallbackMode channelCfg;
      writer = isWriter channelCfg vmName;
      vmCfg = getVmConfig channelCfg vmName;
      source =
        if simple then
          "${channelBase baseDirectory channel}/"
        else if writer then
          writerSharePath baseDirectory channel vmName
        else
          exportRoPath baseDirectory channel;
    in
    {
      tmpfileRule = "d ${vmCfg.mountPoint} ${vmCfg.mode or "0755"} ${vmCfg.user or "root"} ${vmCfg.group or "root"} -";
      share = {
        tag = channel;
        inherit source;
        inherit (vmCfg) mountPoint;
        proto = "virtiofs";
        securityModel = "passthrough";
        readOnly = !simple && !writer;
      };
      filesystem = {
        name = vmCfg.mountPoint;
        value = {
          noCheck = true;
          options = [
            "nodev"
            "nosuid"
            "noexec"
          ]
          ++ (if simple || writer then [ "rw" ] else [ "ro" ]);
        };
      };
    };

  # Build VM notification mapping for a single channel
  # Returns: { mapping } or {}
  mkVmNotifyMapping =
    {
      channel,
      channelCfg,
      vmName,
    }:
    let
      vmCfg = getVmConfig channelCfg vmName;
      wantsNotify = lib.any (m: channelCfg.${m}.${vmName}.notify or false) [
        "readWrite"
        "readOnly"
      ];
    in
    lib.optionalAttrs wantsNotify {
      mapping = "-m ${lib.escapeShellArg "${channel}=${vmCfg.mountPoint}"}";
    };

  # ═══════════════════════════════════════════════════════════════════════════
  # Host Configuration Builders
  # ═══════════════════════════════════════════════════════════════════════════

  # Build host tmpfile rules for a single channel
  # Returns: [ "d /path mode user group -" ... ]
  mkHostTmpfileRules =
    {
      channel,
      channelCfg,
      baseDirectory,
      hostId,
    }:
    let
      base = channelBase baseDirectory channel;
      writers = allWriters channelCfg;
    in
    if isFallbackMode channelCfg then
      [
        "d ${base} 0755 root root -"
        "d ${base}/share 0770 root users -"
      ]
    else
      [
        "d ${base} 0755 root root -"
        "d ${base}/share 0755 root root -"
      ]
      ++ lib.optionals (channelCfg.readOnly != { }) [
        "d ${exportPath baseDirectory channel} 0755 root root -"
        "d ${exportRoPath baseDirectory channel} 0755 root root -"
      ]
      ++ lib.mapAttrsToList (
        w: wcfg: "d ${writerSharePath baseDirectory channel w} ${wcfg.mode} ${wcfg.user} ${wcfg.group} -"
      ) writers
      ++
        lib.optionals (channelCfg.scanning.enable && channelCfg.scanning.infectedAction == "quarantine")
          [
            "d ${base}/quarantine 0700 root root -"
          ]
      ++ lib.optionals (isReader channelCfg hostId) [
        "d ${channelCfg.readOnly.${hostId}.mountPoint} 0755 root root -"
      ];

  # Build host mount configurations for a single channel
  # Returns: [ { what, where, type, options, ... } ... ]
  mkHostMounts =
    {
      channel,
      channelCfg,
      baseDirectory,
      hostId,
    }:
    let
      writers = allWriters channelCfg;
      mountBase = {
        type = "none";
        wantedBy = [ "sysinit.target" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        requires = [ "systemd-tmpfiles-setup.service" ];
        unitConfig.DefaultDependencies = false;
      };
    in
    # export/ -> export-ro/ (ro) for readers
    lib.optional (!isFallbackMode channelCfg && channelCfg.readOnly != { }) (
      mountBase
      // {
        what = exportPath baseDirectory channel;
        where = exportRoPath baseDirectory channel;
        options = "bind,ro";
      }
    )
    # Host reader mount
    ++ lib.optional (isReader channelCfg hostId) (
      mountBase
      // {
        what = exportRoPath baseDirectory channel;
        where = channelCfg.readOnly.${hostId}.mountPoint;
        options = "bind,ro";
      }
    )
    # Host writer mount
    ++ lib.optional (isWriter channelCfg hostId) (
      mountBase
      // {
        what = writerSharePath baseDirectory channel hostId;
        where = writers.${hostId}.mountPoint;
        options = "bind";
      }
    );

  # Build daemon channel configuration
  # Returns: { mode, basePath, producers, consumers, ... }
  mkDaemonChannelConfig =
    {
      channel,
      channelCfg,
      baseDirectory,
      guestCids,
    }:
    {
      inherit (channelCfg) mode debounceMs;
      basePath = channelBase baseDirectory channel;
      producers = lib.attrNames (allWriters channelCfg);
      consumers = lib.attrNames channelCfg.readOnly;
      diodeProducers = lib.attrNames channelCfg.writeOnly;
      scanning = {
        enable = channelCfg.mode != "trusted" && channelCfg.scanning.enable;
        inherit (channelCfg.scanning)
          infectedAction
          permissive
          ignoreFilePatterns
          ignorePathPatterns
          ;
      };
      userNotify = { inherit (channelCfg.userNotify) enable socket; };
    }
    // lib.optionalAttrs (guestCids != [ ]) {
      guestNotify = {
        guests = guestCids;
        inherit (channelCfg.guestNotify) port;
      };
    };

  # Build channel validation assertions
  # Returns: [ { assertion, message } ... ]
  mkChannelAssertions =
    {
      channel,
      channelCfg,
      hostId,
    }:
    let
      hasWriters = (allWriters channelCfg) != { };
      hasReaders = channelCfg.readOnly != { };
    in
    lib.optionals (isFallbackMode channelCfg) [
      {
        assertion = hasWriters || hasReaders;
        message = "Channel '${channel}' with mode 'fallback' must have at least one participant";
      }
      {
        assertion = !(isWriter channelCfg hostId) && !(isReader channelCfg hostId);
        message = "Channel '${channel}' with mode 'fallback' does not support host as participant (use 'untrusted' or 'trusted' mode)";
      }
    ]
    ++ lib.optionals (!isFallbackMode channelCfg) [
      {
        assertion = hasWriters;
        message = "Channel '${channel}' must have at least one writer";
      }
      {
        # Multiple writers share with each other, so explicit readers are optional
        assertion = hasReaders || (lib.length (lib.attrNames (allWriters channelCfg)) >= 2);
        message = "Channel '${channel}' must have at least one reader, or multiple writers";
      }
    ];
}

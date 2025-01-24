# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  IPAccounting = true;
  IPAddressDeny = "any";
  RestrictAddressFamilies = [
    "AF_UNIX"
  ];

  ProtectHome = true;
  ProtectSystem = "full";
  ReadOnlyPaths = [ "/" ];
  PrivateTmp = true;
  PrivateDevices = true;
  DeviceAllow = [
    "/dev/null rw"
    "/dev/urandom r"
  ];

  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  NoNewPrivileges = true;
  UMask = 77;
  ProtectHostname = true;
  ProtectClock = true;
  ProtectControlGroups = true;
  RestrictNamespaces = true;
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  SystemCallArchitectures = "native";
  LimitMEMLOCK = 0;

  AmbientCapabilities = [
    "CAP_BPF"
    "CAP_PERFMON"
  ];
  CapabilityBoundingSet = [
    "CAP_SETGID"
    "CAP_SETUID"
    "CAP_SETPCAP"
    "CAP_SYS_RESOURCE"
    "CAP_AUDIT_WRITE"
  ];

  SystemCallFilter = [
    "@system-service"
    "~@chown"
    "@clock"
    "@cpu-emulation"
    "@debug"
    "@module"
    "@mount"
    "@obsolete"
    "@raw-io"
    "@reboot"
    "@resources"
    "@swap"
    "memfd_create"
    "mincore"
    "mlock"
    "mlockall"
    "personality"
  ];
}

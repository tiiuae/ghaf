# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  IPAccounting = true;
  IPAddressDeny = "any";
  ProtectSystem = "full";
  ProtectProc = "noaccess";
  PrivateMounts = true;
  ProcSubset = "all";
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  NoNewPrivileges = false;
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
  NotifyAccess = "main";

  ReadWritePaths = [
    "/run"
    "/var/"
    "/dev/"
  ];

  RestrictAddressFamilies = [
    "~AF_PACKET"
  ];

  CapabilityBoundingSet = [
    "CAP_IPC_LOCK"
    "CAP_SYS_TTY_CONFIG"
    "CAP_SETGID"
    "CAP_CHOWN"
    "CAP_SETUID"
    "CAP_IPC_OWNER"
    "CAP_DAC_OVERRIDE"
    "CAP_DAC_READ_SEARCH"
  ];

  SystemCallFilter = [
    "mincore"
    "@setuid"
    "@chown"
    "@system-service"
    "@file-system"
    "@basic-io"
    "@ipc"
    "@signal"
    "~@clock"
    "~@cpu-emulation"
    "~@debug"
    "~@module"
    "~@mount"
    "~@obsolete"
    "~@raw-io"
    "~@reboot"
    "~@swap"
  ];
}

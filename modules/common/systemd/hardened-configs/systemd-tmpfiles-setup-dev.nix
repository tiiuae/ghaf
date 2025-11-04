# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = true;
  IPAccounting = true;
  IPAddressDeny = "any";
  RestrictAddressFamilies = "none";
  ProtectHome = true;
  ProtectSystem = "full";
  ProtectProc = "noaccess";
  PrivateTmp = false;
  PrivateMounts = false;
  ProcSubset = "all";
  PrivateUsers = false;
  DynamicUser = false;
  PrivateDevices = false;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  Delegate = false;
  KeyringMode = "private";
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
  RemoveIPC = true;
  SystemCallArchitectures = "native";
  NotifyAccess = "main";

  CapabilityBoundingSet = [
    "CAP_MKNOD"
    "CAP_DAC_OVERRIDE"
    "CAP_SYS_ADMIN"
    "CAP_CHOWN"
  ];

  SystemCallFilter = [
    "~@clock"
    "~@cpu-emulation"
    "~@debug"
    "~@module"
    "~@mount"
    "~@obsolete"
    "~@reboot"
    "~@resources"
    "~@swap"
  ];
}

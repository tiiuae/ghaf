# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = true;
  IPAccounting = true;
  IPAddressDeny = "any";
  RestrictAddressFamilies = "none";
  ProtectHome = true;
  ProtectSystem = "strict";
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
    "CAP_SYS_ADMIN"
  ];

  SystemCallFilter = [
    "~@clock"
    "~@cpu-emulation"
    "~@debug"
    "~@module"
    "~@obsolete"
    "~@reboot"
    "~@resources"
    "~@swap"
  ];
}

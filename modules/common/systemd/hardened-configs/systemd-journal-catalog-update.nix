# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = true;
  IPAccounting = true;
  IPAddressDeny = "any";
  ProtectHome = true;
  ProtectSystem = "full";
  ProtectProc = "noaccess";
  PrivateTmp = true;
  PrivateMounts = true;
  ProcSubset = "pid";
  PrivateUsers = true;
  DynamicUser = false;
  PrivateDevices = true;
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
  RestrictAddressFamilies = "none";

  CapabilityBoundingSet = [
    "CAP_DAC_READ_SEARCH"
    "CAP_DAC_WRITE"
  ];

  SystemCallFilter = [
    "~@clock"
    "~@cpu-emulation"
    "~@debug"
    "~@module"
    "~@mount"
    "~@obsolete"
    "~@privileged"
    "~@raw-io"
    "~@reboot"
    "~@resources"
    "~@swap"
  ];
}

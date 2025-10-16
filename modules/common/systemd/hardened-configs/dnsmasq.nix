# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = false;
  IPAccounting = true;
  IPAddressDeny = "any";
  ProtectHome = true;
  ProtectSystem = true;
  ProtectProc = "noaccess";
  PrivateTmp = true;
  PrivateMounts = true;
  ProcSubset = "pid";
  PrivateUsers = false;
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

  RestrictAddressFamilies = [
    "~AF_PACKET"
  ];

  CapabilityBoundingSet = [
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_RAW"
    "CAP_SYS_RESOURCE"
    "CAP_SETGID"
    "CAP_SETUID"
    "CAP_CHOWN"
    "CAP_DAC_OVERRIDE"
  ];

  SystemCallFilter = [
    "~@clock"
    "~@debug"
    "~@module"
    "~@mount"
    "~@obsolete"
    "~@reboot"
    "~@resources"
    "~@swap"
  ];
}

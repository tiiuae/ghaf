# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = true;
  IPAccounting = true;
  IPAddressDeny = "any";
  ProtectHome = true;
  ProtectSystem = true;
  ProtectProc = "noaccess";
  PrivateTmp = true;
  PrivateMounts = false;
  ProcSubset = "pid";
  PrivateUsers = true;
  DynamicUser = false;
  PrivateDevices = false;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = false;
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
    "~AF_NETLINK"
    "~AF_UNIX"
    "~AF_INET"
    "~AF_INET6"
  ];

  CapabilityBoundingSet = [
    "CAP_SYS_NICE"
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

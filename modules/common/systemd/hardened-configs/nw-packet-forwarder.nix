# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  AmbientCapabilities = "CAP_NET_RAW";
  CapabilityBoundingSet = "CAP_NET_RAW";
  PrivateNetwork = false;
  IPAccounting = true;
  IPAddressDeny = "any";
  ProtectHome = true;
  ProtectSystem = "strict";
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
    "AF_NETLINK"
    "AF_UNIX"
    "AF_PACKET"
    "~AF_INET"
    "~AF_INET6"
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

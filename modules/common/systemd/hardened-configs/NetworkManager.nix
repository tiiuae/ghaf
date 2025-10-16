# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = false;
  IPAccounting = true;
  ProtectHome = true;
  ProtectSystem = true;
  ProtectProc = "ptraceable";
  PrivateTmp = true;
  PrivateMounts = true;
  ProcSubset = "pid";
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
  SystemCallArchitectures = "native";
  NotifyAccess = "main";

  RestrictAddressFamilies = [
    "AF_INET"
    "AF_INET6"
    "AF_NETLINK"
    "AF_PACKET"
    "AF_UNIX"
  ];

  CapabilityBoundingSet = [
    "CAP_AUDIT_READ"
    "CAP_DAC_READ_SEARCH"
    "CAP_FOWNER"
    "CAP_IPC_OWNER"
    "CAP_NET_ADMIN"
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_BROADCAST"
    "CAP_NET_RAW"
    "CAP_SYS_RESOURCE"
    "CAP_SETGID"
    "CAP_SETPCAP"
    "CAP_FSETID"
    "CAP_SETFCAP"
  ];

  SystemCallFilter = [
    "~@clock"
    "~@debug"
    "~@module"
    "~@mount"
    "~@obsolete"
    "~@raw-io"
    "~@reboot"
    "~@resources"
    "~@swap"
    "~@cpu-emulation"
  ];
}

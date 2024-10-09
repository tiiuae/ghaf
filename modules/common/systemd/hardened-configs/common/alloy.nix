# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  IPAccounting = true;
  IPAddressAllow = [
    "192.168.100.0/24"
    "192.168.101.0/24"
  ];
  RestrictAddressFamilies = [ "~AF_INET6" ];

  ProtectHome = true;
  ProtectSystem = "full";
  ProtectProc = true;
  PrivateUsers = true;
  DynamicUser = true;
  PrivateDevices = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  NoNewPrivileges = true;
  UMask = 27;
  ProtectHostname = true;
  ProtectClock = true;
  ProtectControlGroups = true;
  RestrictNamespaces = true;
  MemoryDenyWriteExecute = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  RemoveIPC = true;
  SystemCallArchitectures = "native";

  CapabilityBoundingSet = [
    "CAP_AUDIT_READ"
    "CAP_IPC_LOCK"
    "CAP_IPC_OWNER"
    "CAP_KILL"
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_BROADCAST"
    "CAP_NET_RAW"
    "CAP_SYS_PTRACE"
    "CAP_SYS_RAWIO"
    "CAP_SYSLOG"
  ];

  SystemCallFilter = [
    "@privileged"
    "@system-service"
    "~@aio"
    "~@keyring"
    "~@memlock"
    "~@timer"
    "~@reboot"
    "~@swap"
    "~@chown"
    "~@module"
    "~@clock"
  ];
}

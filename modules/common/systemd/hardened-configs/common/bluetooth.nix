# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  ProtectProc = "noaccess";
  ProcSubset = "pid";
  ProtectHome = true;
  ProtectSystem = "full";
  PrivateTmp = true;
  PrivateMounts = true;
  UMask = 77;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  KeyringMode = "private";
  ProtectHostname = true;
  ProtectClock = true;
  ProtectControlGroups = true;
  RestrictRealtime = true;
  RemoveIPC = true;
  NotifyAccess = "all";
  NoNewPrivileges = true;
  RestrictSUIDSGID = true;
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  IPAddressDeny = "any";
  RestrictAddressFamilies = [
    "AF_BLUETOOTH"
    "AF_ALG"
    "AF_UNIX"
  ];
  ReadWritePaths = [ "/var/lib/bluetooth" ];
  DeviceAllow = [
    "/dev/rfkill"
    "/dev/uinput"
  ];
  RestrictNamespaces = [
    "~user"
    "~pid"
    "~net"
    "~uts"
    "~mnt"
    "~cgroup"
    "~ipc"
  ];
  AmbientCapabilities = [
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_ADMIN"
    "CAP_NET_RAW"
    "CAP_SYS_RESOURCE"
    "CAP_AUDIT_WRITE"
  ];
  CapabilityBoundingSet = [
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_ADMIN"
    "CAP_NET_RAW"
    "CAP_SYS_RESOURCE"
    "CAP_AUDIT_WRITE"
  ];
  SystemCallArchitectures = "native";
  SystemCallFilter = [
    "~@swap"
    "~@timer"
    "~@pkey"
    "~@debug"
    "~@cpu_emulation"
    "~@mount"
    "~@ipc"
    "~@resources"
    "~@memlock"
    "~@keyring"
    "~@raw_io"
    "~@clock"
    "~@aio"
    "~@setuid"
    "~@module"
    "~@reboot"
    "~@sandbox"
    "~@chown"
  ];
}

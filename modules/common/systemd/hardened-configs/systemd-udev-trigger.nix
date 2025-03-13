# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = false;
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
  PrivateDevices = true;
  DeviceAllow = [ "/dev/null rw" ];
  ProtectKernelTunables = false;
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
    "~CAP_SYS_PACCT"
    "~CAP_KILL"
    "~CAP_WAKE_ALARM"
    "~CAP_FOWNER"
    "~CAP_IPC_OWNER"
    "~CAP_BPF"
    "~CAP_LINUX_IMMUTABLE"
    "~CAP_IPC_LOCK"
    "~CAP_SYS_MODULE"
    "~CAP_SYS_TTY_CONFIG"
    "~CAP_SYS_BOOT"
    "~CAP_SYS_CHROOT"
    "~CAP_BLOCK_SUSPEND"
    "~CAP_LEASE"
    "~CAP_MKNOD"
    "~CAP_CHOWN"
    "~CAP_FSETID"
    "~CAP_SETFCAP"
    "~CAP_MAC_ADMIN"
    "~CAP_MAC_OVERRIDE"
    "~CAP_SYS_RAWIO"
    "~CAP_SYS_PTRACE"
    "~CAP_NET_ADMIN"
    "~CAP_NET_BIND_SERVICE"
    "~CAP_NET_BROADCAST"
    "~CAP_NET_RAW"
    "~CAP_SYS_ADMIN"
    "~CAP_SYSLOG"
    "~CAP_SYS_TIME"
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

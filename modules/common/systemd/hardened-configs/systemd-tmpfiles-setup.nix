# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = false;
  IPAccounting = true;
  IPAddressDeny = "any";
  RestrictAddressFamilies = "none";
  ProtectHome = false;
  ProtectSystem = true;
  ProtectProc = "noaccess";
  PrivateTmp = false;
  PrivateMounts = false;
  PrivateUsers = false;
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
  RestrictSUIDSGID = false;
  RemoveIPC = true;
  SystemCallArchitectures = "native";
  NotifyAccess = "main";

  CapabilityBoundingSet = [
    "CAP_DAC_READ_SEARCH"
    "CAP_DAC_OVERRIDE"
    "CAP_CHOWN"
    "CAP_FOWNER"
    "CAP_SYS_ADMIN"
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

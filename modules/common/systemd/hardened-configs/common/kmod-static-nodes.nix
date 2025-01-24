# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = true;
  IPAddressDeny = "any";
  RestrictAddressFamilies = "none";
  RestrictNamespaces = true;
  ProtectProc = "noaccess";
  PrivateMounts = true; # ##
  PrivateUsers = true;
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
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  SystemCallArchitectures = "native";
  NotifyAccess = "main";

  CapabilityBoundingSet = [
    "CAP_SYS_MODULE"
    "CAP_MKNOD"
    "CAP_SYS_ADMIN"
  ];

  ################
  # System calls #
  ################

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

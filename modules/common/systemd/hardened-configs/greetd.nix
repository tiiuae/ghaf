# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  ##############
  # Networking #
  ##############
  IPAccounting = true;
  IPAddressDeny = "any";
  RestrictAddressFamilies = [
    "~AF_PACKET"
  ];

  ###############
  # File system #
  ###############

  ProtectSystem = "full";
  ProtectProc = "noaccess";
  ReadWritePaths = [
    "/run"
    "/var/"
    "/dev/"
  ];

  PrivateMounts = true;
  ProcSubset = "all";

  ##########
  # Kernel #
  ##########

  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;

  ########
  # Misc #
  ########
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
  NotifyAccess = false;

  ################
  # Capabilities #
  ################

  CapabilityBoundingSet = [
    "CAP_IPC_LOCK"
    "CAP_SYS_TTY_CONFIG"
    "CAP_SETGID"
    "CAP_CHOWN"
    "CAP_SETUID"
    "CAP_IPC_OWNER"
    "CAP_DAC_OVERRIDE"
    "CAP_DAC_READ_SEARCH"
  ];

  ################
  # System calls #
  ################
  SystemCallFilter = [
    "@setuid"
    "@chown"
    "@system-service"
    "@file-system"
    "@basic-io"
    "@ipc"
    "@signal"
    "~@clock"
    "~@cpu-emulation"
    "~@debug"
    "~@module"
    "~@mount"
    "~@obsolete"
    "~@raw-io"
    "~@reboot"
    "~@swap"
  ];
}

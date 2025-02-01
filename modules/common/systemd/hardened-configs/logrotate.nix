# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = true;
  IPAccounting = true;
  IPAddressDeny = "any";
  ProtectHome = true;
  ProtectSystem = "full";
  ProtectProc = "invisible";
  PrivateTmp = true;
  PrivateMounts = true;
  ProcSubset = "pid";
  PrivateUsers = true;
  DynamicUser = false;
  PrivateDevices = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  Delegate = false;
  KeyringMode = "private";
  NoNewPrivileges = true;
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
  RestrictAddressFamilies = "none";

  CapabilityBoundingSet = [
    "CAP_CHOWN"
    "CAP_DAC_OVERRIDE"
    "CAP_FOWNER"
    "CAP_KILL"
    "CAP_SETUID"
    "CAP_SETGID"
  ];

  SystemCallFilter = [
    "@system-service"
    "~@privileged"
    "@resources"
    "@chown"
    "@setuid"
  ];
}

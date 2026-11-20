# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  AmbientCapabilities = "";
  CapabilityBoundingSet = "";
  DevicePolicy = "closed";
  LockPersonality = true;
  LimitNOFILE = 128;
  MemoryMax = "256M";
  MemoryDenyWriteExecute = true;
  NoNewPrivileges = true;
  PrivateDevices = true;
  PrivateNetwork = true;
  ProcSubset = "pid";
  ProtectClock = true;
  ProtectControlGroups = true;
  ProtectHome = true;
  ProtectHostname = true;
  ProtectKernelLogs = true;
  ProtectKernelModules = true;
  ProtectKernelTunables = true;
  ProtectProc = "invisible";
  ProtectSystem = "strict";
  RemoveIPC = true;
  RestrictAddressFamilies = [ "AF_UNIX" ];
  RestrictNamespaces = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  SystemCallArchitectures = "native";
  TasksMax = 64;
  UMask = "0077";
}

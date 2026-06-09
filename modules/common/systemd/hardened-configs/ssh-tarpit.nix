# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  ##############
  # Networking #
  ##############

  RestrictAddressFamilies = [
    "AF_INET"
    "AF_INET6"
  ];

  ###############
  # File system #
  ###############

  PrivateTmp = true;
  ProtectHome = true;
  ProtectSystem = "strict";
  ProtectProc = "noaccess";
  ProcSubset = "pid";

  ###################
  # User separation #
  ###################

  PrivateUsers = true;
  DynamicUser = true;
  RootDirectory = "/run/ssh-tarpit";
  BindReadOnlyPaths = [
    builtins.storeDir
    "-/etc/hosts"
    "-/etc/localtime"
    "-/etc/nsswitch.conf"
    "-/etc/resolv.conf"
  ];
  InaccessiblePaths = [ "-+/run/ssh-tarpit" ];
  RuntimeDirectory = "ssh-tarpit";
  RuntimeDirectoryMode = "700";

  ###########
  # Devices #
  ###########

  PrivateDevices = true;

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
  UMask = "0077";
  ProtectHostname = true;
  ProtectClock = true;
  ProtectControlGroups = true;
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  RemoveIPC = true;
  RestrictNamespaces = true;
  SystemCallArchitectures = "native";
  SystemCallFilter = [
    "@system-service"
    "~@privileged"
  ];

  ################
  # Capabilities #
  ################

  AmbientCapabilities = [ "" ];
  CapabilityBoundingSet = [ "" ];
}

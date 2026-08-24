# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  PrivateNetwork = false;
  IPAccounting = true;
  ProtectHome = true;
  ProtectSystem = "strict";
  # strict mounts the whole hierarchy read-only apart from /dev, /proc and /sys.
  # Dispatcher scripts publish runtime state under /run (Ghaf's own uplink
  # dispatcher restarts a unit that writes there), so without this they fail on
  # the first write. NOTE: this drop-in previously targeted
  # "NetworkManager-Dispatcher", which is not a real unit name, so it has never
  # actually been applied -- it needs a runtime check on the host and net-vm.
  ReadWritePaths = [ "/run" ];
  ProtectProc = "noaccess";
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
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  SystemCallArchitectures = "native";
  NotifyAccess = "main";
  RestrictNamespaces = true;

  RestrictAddressFamilies = [
    "AF_INET"
    "AF_INET6"
    "AF_NETLINK"
    "AF_PACKET"
    "AF_UNIX"
  ];

  CapabilityBoundingSet = [
    "CAP_FOWNER"
    #"CAP_NET_ADMIN"
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_BROADCAST"
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
    "~@privileged"
    "~@raw-io"
    "~@reboot"
    "~@resources"
    "~@swap"
    "~@cpu-emulation"
  ];
}

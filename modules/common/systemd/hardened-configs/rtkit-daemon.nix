# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  ##############
  # Networking #
  ##############

  # PrivateNetwork=true;
  # IPAccounting=yes
  # IPAddressDeny="any";
  RestrictAddressFamilies = [
    "~AF_PACKET"
    #"~AF_NETLINK"
    #"~AF_UNIX"
    #"~AF_INET"
    #"~AF_INET6"
  ];

  ###############
  # File system #
  ###############

  ProtectHome = true;
  ProtectSystem = "strict";
  # ProtectProc = "invisible"; #inherit from nixos modules security systemd modules
  # ReadWritePaths=[ "/etc"];
  # PrivateTmp = "disconnected"; #inherit from nixos modules security systemd modules

  # Not applicable for the service runs as root
  # PrivateMounts=true;
  # ProcSubset="all";

  ###################
  # User separation #
  ###################

  # Not applicable for the service runs as root
  # PrivateUsers=true;
  # DynamicUser=true;

  ###########
  # Devices #
  ###########

  # PrivateDevices=false;
  # DeviceAllow=/dev/null

  ##########
  # Kernel #
  ##########

  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;

  ########
  # Misc #
  ########

  # Delegate=false;
  # KeyringMode="private";
  NoNewPrivileges = true;
  # UMask=077;
  ProtectHostname = true;
  ProtectClock = true;
  # ProtectControlGroups=true;
  # RestrictNamespaces=true;
  /*
      RestrictNamespaces=[
     #"~user"
     #"~pid"
     #"~net"
     #"~uts"
     #"~mnt"
     #"~cgroup"
     #"~ipc"
    ];
  */
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  # RestrictRealtime=true;
  RestrictSUIDSGID = true;
  # RemoveIPC=true
  SystemCallArchitectures = "native";
  # NotifyAccess=false;

  ################
  # Capabilities #
  ################

  #AmbientCapabilities=
  CapabilityBoundingSet = [
    "~CAP_SYS_PACCT"
    "~CAP_KILL"
    # "~CAP_WAKE_ALARM"
    # "~CAP_DAC_*
    # "~CAP_FOWNER"
    # "~CAP_IPC_OWNER"
    # "~CAP_BPF"
    "~CAP_LINUX_IMMUTABLE"
    # "~CAP_IPC_LOCK"
    "~CAP_SYS_MODULE"
    "~CAP_SYS_TTY_CONFIG"
    "~CAP_SYS_BOOT"
    # "~CAP_SYS_CHROOT"
    "~CAP_BLOCK_SUSPEND"
    "~CAP_LEASE"
    "~CAP_MKNOD"
    # "~CAP_CHOWN"
    # "~CAP_FSETID"
    # "~CAP_SETFCAP"
    # "~CAP_SETUID"
    # "~CAP_SETGID"
    # "~CAP_SETPCAP"
    # "~CAP_MAC_ADMIN"
    # "~CAP_MAC_OVERRIDE"
    "~CAP_SYS_RAWIO"
    "~CAP_SYS_PTRACE"
    # "~CAP_SYS_NICE"
    # "~CAP_SYS_RESOURCE"
    # "~CAP_NET_ADMIN"
    # "~CAP_NET_BIND_SERVICE"
    # "~CAP_NET_BROADCAST"
    # "~CAP_NET_RAW"
    # "~CAP_AUDIT_CONTROL"
    # "~CAP_AUDIT_READ"
    # "~CAP_AUDIT_WRITE"
    # "~CAP_SYS_ADMIN"
    # "~CAP_SYSLOG"
    # "~CAP_SYS_TIME
  ];

  ################
  # System calls #
  ################

  SystemCallFilter = [
    "~@clock"
    "~@cpu-emulation"
    "~@debug"
    "~@module"
    # "~@mount"
    "~@obsolete"
    # "~@privileged"
    "~@raw-io"
    "~@reboot"
    # "~@resources"
    "~@swap"
  ];
}

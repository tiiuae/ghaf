<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

This document outlines systemd service configurations that significantly impact a service's exposure. These configurations can be utilized to enhance the security of a systemd service.

# Table Of Contents:

### Networking
- [PrivateNetwork](#PrivateNetwork)
- [IPAccounting](#IPAccounting)
- [IPAddressDeny](#IPAddressDeny)
- [RestrictAddressFamilies](#RestrictAddressFamilies)

### File system
- [ProtectHome](#ProtectHome)
- [ProtectSystem](#ProtectSystem)
- [ProtectProc](#ProtectProc)
- [ReadWritePaths](#ReadWritePaths);
- [PrivateTmp](#PrivateTmp)
- [PrivateMounts](#PrivateMounts)
- [ProcSubset](#ProcSubset)

### User separation
- [PrivateUsers](#PrivateUsers)
- [DynamicUser](#DynamicUser)

### Devices 

- [PrivateDevices](#PrivateDevices)
- [DeviceAllow](#DeviceAllow)

### Kernel 
- [ProtectKernelTunables](#ProtectKernelTunables)
- [ProtectKernelModules](#ProtectKernelModules)
- [ProtectKernelLogs](#ProtectKernelLogs)

### Misc 
- [Delegate](#Delegate)
- [KeyringMode](#KeyringMode)
- [NoNewPrivileges](#NoNewPrivileges)
- [UMask](#UMask)
- [ProtectHostname](#ProtectHostname)
- [ProtectClock](#ProtectClock)
- [ProtectControlGroups](#ProtectControlGroups)
- [RestrictNamespaces](#RestrictNamespaces)
- [LockPersonality](#LockPersonality)
- [MemoryDenyWriteExecute](#MemoryDenyWriteExecute)
- [RestrictRealtime](#RestrictRealtime)
- [RestrictSUIDSGID](#RestrictSUIDSGID)
- [RemoveIPC](#RemoveIPC)
- [SystemCallArchitectures](#SystemCallArchitectures)
- [NotifyAccess](#NotifyAccess)

### Capabilities 
- [AmbientCapabilities](#AmbientCapabilities)
- [CapabilityBoundingSet](#CapabilityBoundingSet)
  
### System calls
- [SystemCallFilter](#SystemCallFilter)

---

# Networking

### PrivateNetwork

Useful for preventing the service from accessing the network.

**Type**: *boolean*

**Default**: `false`

**Options**:

- `true` : Creates a new network namespace for the service. Only the loopback device "lo" is available in this namespace, other network devices are not accessible.
- `false` : The service will use the host's network namespace, it can access all the network devices available on host. It can communicate over the network like any other process running on host.

[PrivateNetwork](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#PrivateNetwork=)

---

### IPAccounting

Helps in detecting unusual or unexpected network activity by a service.

**Type**: *boolean*

**Default**: `false`

**Options**:
- `true`: Enables accounting for all IPv4 and IPv6 sockets created by the service, i.e. keeps track of the data sent and received by each socket in the service.\  
- `false`: Disables tracking of the sockets created by the service.

[IPAccounting](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#IPAccounting=)

---

### IPAddressAllow=ADDRESS[/PREFIXLENGTH]…,
### IPAddressDeny=ADDRESS[/PREFIXLENGTH]…

It enables packet filtering on all IPv4 and IPv6 sockets created by the service. Useful for restricting/preventing a service to communicate only with certain IP addresses or networks.

**Type**: *Space separated list of ip addresses and/or a symbloc name*

**Default**: All IP addresses are allowed and no IP addresses are explicitly denied.

**Options**: 
- *List of addresses*: Specify list of addresses allowed/denied e.g. `['192.168.1.8' '192.168.1.0/24']`. Any IP not explicitly allowed will be denied.
- *Symbolic Names*: Following symbolic names can also be used.\
    `any` :	Any host (i.e. '0.0.0.0/0 ::/0')\
    `localhost`: All addresses on the local loopback(i.e. '127.0.0.0/8 ::1/128')\
    `link-local`: All link-local IP addresses(i.e.'169.254.0.0/16 fe80::/64')\
    `multicast`: All IP multicasting addresses (i.e. 224.0.0.0/4 ff00::/8)\

[IPAddressAllow](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#IPAddressAllow=)
   
---

### RestrictNetworkInterfaces

Used to control which network interfaces a service has access to. This helps isolate services from the network or restrict them to specific network interfaces, enhancing security and reducing potential risk.

**Type**: *Space separated list of network interface names.*

**Default**: The service has access to all available network interfaces unless other network restrictions are in place. 

**Options**:
- Specify individual network interface names to restrict the service to using only those interfaces.
- Prefix an interface name with '~' to invert the restriction, i.e. denying access to that specific interface while allowing all others.

[RestrictNetworkInterfaces](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#RestrictNetworkInterfaces=)

---

### RestrictAddressFamilies

Used to control which address families a service can use. This setting restricts the service's ability to open sockets using specific address families, such as `'AF_INET'` for IPv4, `'AF_INET6'` for IPv6, or others. It is a security feature that helps limit the service's network capabilities and reduces its exposure to network-related vulnerabilities.

**Type**: List of address family names.

**Default**: If not configured, the service is allowed to use all available address families.

**Options**:
- **`none`**: Apply no restriction.
- **Specific Address Families**: Specify one or more address families that the service is allowed to use, e.g., `'AF_INET'`, `'AF_INET6'`, `'AF_UNIX'`.
- **Inverted Restriction**: Prepend character '~' to an address family name to deny access to it while allowing all others, e.g., `'~AF_INET'` would block IPv4 access.
   
[RestrictAddressFamilies](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RestrictAddressFamilies=)

---

# File system

### ProtectHome

Used to restrict a service's access to home directories. This security feature can be used to either completely block access to `/home`, `/root`, and `/run/user` or make them appear empty to the service, thereby protecting user data from unauthorized access by system services.

**Type**: *Boolean or string.*

**Default**: `false` i.e. the service has full access to home directories unless restricted by some other mean.

**Options**:
- **`true`**: The service is completely denied access to home directories.
- **`false`**: The service has unrestricted access to home directories.
- **`read-only`**: The service can view the contents of home directories but cannot modify them.
- **`tmpfs`**: Mounts a temporary filesystem in place of home directories, ensuring the service cannot access or modify the actual user data. Adding the tmpfs option provides a flexible approach by creating a volatile in-memory filesystem where the service believes it has access to home but any changes it makes do not affect the actual data and are lost when the service stops. This is particularly useful for services that require a temporary space in home.
  
[ProtectHome](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectHome=)

---

### ProtectSystem

Controls access to the system's root directory (`/`) and other essential system directories. This setting enhances security by restricting a service's ability to modify or access critical system files and directories.

**Type**: *Boolean or string.*

**Default**: `full` (Equivalent to `true`). The service is restricted from modifying or accessing critical system directories.

**Options**:
- **`true`**: Mounts the directories `/usr/`, `/boot`, and `/efi` read-only for processes.
- **`full`**: Additionally mounts the `/etc/` directory read-only.
- **`strict`**: Mounts the entire file system hierarchy read-only, except for essential API file system subtrees like `/dev/`, `/proc/`, and `/sys/`.
- **`false`**: Allows the service unrestricted access to system directories.

Using `true` or `full` is recommended for services that do not require access to system directories to enhance security and stability.

[ProtectSystem](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectSystem=)

---

### ProtectProc

Controls access to the `/proc` filesystem for a service. This setting enhances security by restricting a service's ability to view or manipulate processes and kernel information in the `/proc` directory.

**Type**: *Boolean or string.*

**Default**: `default`. No restriction is imposed from viewing or manipulating processes and kernel information in `/proc`.

**Options**:
- **`noaccess`**: Restricts access to most process metadata of other users in `/proc`.
- **`invisible`**: Hides processes owned by other users from view in `/proc`.
- **`ptraceable`**: Hides processes that cannot be traced (`ptrace()`) by other processes.
- **`default`**: Imposes no restrictions on access or visibility to `/proc`.
  
[ProtectProc](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectProc=)

---

### ReadWritePaths, ReadOnlyPaths, InaccessiblePaths, ExecPaths, NoExecPaths

Creates a new file system namespace for executed processes, enabling fine-grained control over file system access.\
- **ReadWritePaths=**: Paths listed here are accessible with the same access modes from within the namespace as from outside it.
- **ReadOnlyPaths=**: Allows reading from listed paths only; write attempts are refused even if file access controls would otherwise permit it.
- **InaccessiblePaths=**: Makes listed paths and everything below them in the file system hierarchy inaccessible to processes within the namespace.
- **NoExecPaths=**: Prevents execution of files from listed paths, overriding usual file access controls. Nest `ExecPaths=` within `NoExecPaths=` to selectively allow execution within directories otherwise marked non-executable.

**Type**: *Space separated list of paths.*

**Default**: No restriction to file system access until unless restricted by some other mechanism.

**Options**:

**Space separated list of paths** : Space-separated list of paths relative to the host's root directory. Symlinks are resolved relative to the root directory specified by `RootDirectory=` or `RootImage=`.

[ReadWritePaths](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ReadWritePaths=)

---

### PrivateTmp

Uses a private, isolated `/tmp` directory for the service, enhancing security by preventing access to other processes' temporary files and ensuring data isolation.

**Type**: *Boolean.*

**Default**: `false`. If not specified, the service shares the system `/tmp` directory with other processes.

**Options**:
- **`true`**: Enables private `/tmp` for the service, isolating its temporary files from other processes.
- **`false`**: The service shares the system `/tmp` directory with other processes.

Additionally, when enabled, all temporary files created by a service in these directories will be automatically removed after the service is stopped.

[PrivateTmp](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#PrivateTmp=)

---

### PrivateMounts

Controls whether the service should have its own mount namespace, isolating its mounts from the rest of the system. This setup ensures that any file system mount points created or removed by the unit's processes remain private to them and are not visible to the host.

**Type**: *Boolean.*

**Default**: `false`. If not specified, the service shares the same mount namespace as other processes.

**Options**:
- **`true`**: Enables private mount namespace for the service, isolating its mounts from the rest of the system.
- **`false`**: The service shares the same mount namespace as other processes.
  
[PrivateMounts](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#PrivateMounts=)

---

### ProcSubset

Restricts the set of `/proc` entries visible to the service, enhancing security by limiting access to specific process information in the `/proc` filesystem.

**Type**: *string*

**Default**: `all`. If not specified, the service has access to all `/proc` entries.

**Options**:
- **`all`**: Allows the service access to all `/proc` entries.
- **`pid`**: Restricts the service to only its own process information (`/proc/self`, `/proc/thread-self/` ).

[ProcSubset](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProcSubset=)

---

# User separation

**NOTE:** Not applicable for the service runs as root

### PrivateUsers

Controls whether the service should run with a private set of UIDs and GIDs, isolating the user and group databases used by the unit from the rest of the system, creating a secure sandbox environment. The isolation reduces the privilege escalation potential of services.

**Type**: *Boolean.*

**Default**: `false`. If not specified, the service runs with the same user and group IDs as other processes.

**Options**:
- **`true`**: Enables private user and group IDs for the service by creating a new user namespace, isolating them from the rest of the system.
- **`false`**: The service runs with the same user and group IDs as other processes.

[PrivateUsers=](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#PrivateUsers=)

---

### DynamicUser

Enables systemd to dynamically allocate a unique user and group ID (UID/GID) for the service at runtime, enhancing security and resource isolation. These user and group entries are managed transiently during runtime and are not added to `/etc/passwd` or `/etc/group`.

**Type**: *Boolean.*

**Default**: `false`. If not specified, the service uses a static user and group ID defined in the service unit file or defaults to `root`.

**Options**:
- **`true`**: A UNIX user and group pair are dynamically allocated when the unit is started and released as soon as it is stopped.
- **`false`**: The service uses a static UID/GID defined in the service unit file or defaults to `root`.

[DynamicUser](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#DynamicUser=)

---

# Devices 

### PrivateDevices

Controls whether the service should have access to device nodes in `/dev`. 

**Type**: *Boolean.*

**Default**: `false`. If not specified, the service has access to device nodes in `/dev`.

**Options**:
- **`true`**: Restricts the service's access to device nodes in `/dev` by creating a new `/dev/` mount for the executed processes and includes only pseudo devices such as `/dev/null`, `/dev/zero`, or `/dev/random`. Physical devices are not added to this mount. This setup is useful for disabling physical device access by the service.
- **`false`**: The service has access to device nodes in `/dev`.
  
[PrivateDevices](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#PrivateDevices=)
   
---

### DeviceAllow

Specifies individual device access rules for the service, allowing fine-grained control over device permissions.

**Type**: *Space-separated list of device access rules.*

**Default**: None. If not specified, the service does not have specific device access rules defined.

**Options**:
- Specify device access rules in the format: `<device path> <permission>` where `<permission>` can be `r` (read), `w` (write), or `m` (mknod, allowing creation of devices).

[DeviceAllow](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#DeviceAllow=)

---

# Kernel

### ProtectKernelTunables

Controls whether the service is allowed to modify tunable kernel variables in `/proc/sys`, enhancing security by restricting access to critical kernel parameters.

**Type**: *Boolean.*

**Default**: `true`. If not specified, the service is restricted from modifying kernel variables.

**Options**:
- **`true`**: Restricts the service from modifying the kernel variables accessible through paths like `/proc/sys/`, `/sys/`, `/proc/sysrq-trigger`, `/proc/latency_stats`, `/proc/acpi`, `/proc/timer_stats`, `/proc/fs`, and `/proc/irq`. These paths are made read-only to all processes of the unit.
- **`false`**: Allows the service to modify tunable kernel variables.

[ProtectKernelTunables](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectKernelTunables=)

---

### ProtectKernelModules

Controls whether the service is allowed to load or unload kernel modules, enhancing security by restricting module management capabilities.

**Type**: *Boolean.*

**Default**: `true`. If not specified, the service is restricted from loading or unloading kernel modules.

**Options**:
- **`true`**: Restricts the service from loading or unloading kernel modules. It removes `CAP_SYS_MODULE` from the capability bounding set for the unit and installs a system call filter to block module system calls. `/usr/lib/modules` is also made inaccessible.
- **`false`**: Allows the service to load or unload kernel modules in modular kernel.

[ProtectKernelModules](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectKernelModules=)

---

### ProtectKernelLogs

Controls whether the service is allowed to access kernel log messages, enhancing security by restricting access to kernel logs.

**Type**: *Boolean.*

**Default**: `false`. If not specified, the service is allowed to access kernel logs.

**Options**:
- **`trues`**: Restricts the service from accessing kernel logs from `/proc/kmsg` and `/dev/kmsg`. Enabling this option removes `CAP_SYSLOG` from the capability bounding set for the unit and installs a system call filter to block the syslog(2) system call. 
- **`no`**: Allows the service to access kernel logs.
  
[ProtectKernelLogs](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectKernelLogs=)

---

# Misc

### Delegate

Controls whether systemd should delegate further control of resource management to the service's own resource management settings.

**Type**: *Boolean.*

**Default**: `true`. If not specified, systemd delegates control to the service's resource management settings.

**Options**:
- **`true`**: Enables delegation and activates all supported controllers for the unit, allowing its processes to manage them.
- **`false`**: Disables delegation entirely. Systemd retains control over resource management, potentially overriding the service's settings.

[Delegate](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#Delegate=)

---

### KeyringMode

Specifies the handling mode for session keyrings by the service, controlling how it manages encryption keys and credentials.

**Type**: *String.*

**Default**: `private`. If not specified, the service manages its session keyrings privately.

**Options**:
- **`private`**: Service manages its session keyrings privately.
- **`shared`**: Service shares its session keyrings with other services and processes.
- **`inherit`**: Service inherits session keyrings from its parent process or environment.

[KeyringMode](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#KeyringMode=)

---
  
### NoNewPrivileges

Controls whether the service and its children processes are allowed to gain new privileges (capabilities).

**Type**: *Boolean.*

**Default**: `false`. If not specified, the service and its children processes can gain new privileges.

**Options**:
- **`true`**: Prevents the service and its children processes from gaining new privileges.
- **`false`**: Allows the service and its children processes to gain new privileges.

Some configurations may override this setting and ignore its value.

[NoNewPrivileges](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#NoNewPrivileges=)

---

### UMask

Sets the file mode creation mask (umask) for the service, controlling the default permissions applied to newly created files and directories.

**Type**: *Octal numeric value.*

**Default**:  If not specified, inherits the default umask of the systemd service manager(0022).

**Example**: `UMask=027`

[UMask](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#UMask=)

---

### ProtectHostname

Controls whether the service can modify its own hostname.

**Type**: *Boolean.*

**Default**: `false`

**Options**:
- **`true`**: Sets up a new UTS namespace for the executed processes. It prevents changes to the hostname or domainname.
- **`false`**: Allows the service to modify its own hostname.

[ProtectHostname](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectHostname=)

---

### ProtectClock

Controls whether the service is allowed to manipulate the system clock.

**Type**: *Boolean.*

**Default**: `false`.

**Options**:
- **`true`**: Prevents the service from manipulating the system clock. It removes `CAP_SYS_TIME` and `CAP_WAKE_ALARM` from the capability bounding set for this unit. Also creates a system call filter to block calls that can manipulate the system clock.
- **`false`**: Allows the service to manipulate the system clock.
**Type**:

[ProtectClock](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectClock=)

---

### ProtectControlGroups

Controls whether the service is allowed to modify control groups (cgroups) settings.

**Type**: *Boolean.*

**Default**: `false`

**Options**:
- **`true`**: Prevents the service from modifying cgroups settings. Makes the Linux Control Groups (cgroups(7)) hierarchies accessible through `/sys/fs/cgroup/` read-only to all processes of the unit.
- **`false`**: Allows the service to modify cgroups settings.

[ProtectControlGroups](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ProtectControlGroups=)

---

### RestrictNamespaces

Controls the namespace isolation settings for the service, restricting or allowing namespace access.

**Type**: *Boolean* or *space-separated list of namespace type identifiers*.

**Default**: `false`.

**Options**:
- `false`: No restrictions on namespace creation and switching are imposed.
- `true`: Prohibits access to any kind of namespacing.
- Otherwise: Specifies a space-separated list of namespace type identifiers, which can include `cgroup`, `ipc`, `net`, `mnt`, `pid`, `user`, and `uts`. When the namespace identifier is prefixed with '~', it inverts the action. 

[RestrictNamespaces](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RestrictNamespaces=)

---

### LockPersonality

Applies restriction on the service's ability to change its execution personality.

**Type**: *Boolean.*

**Default**: `false`

**Options**:
- **`true`**: Prevents the service from changing its execution personality. If the service runs in user mode or in system mode without the `CAP_SYS_ADMIN` capability (e.g., setting `User=`), enabling this option implies `NoNewPrivileges=yes`.
- **`false`**: Allows the service to change its execution personality.

[LockPersonality](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#LockPersonality=)
   
---

### MemoryDenyWriteExecute

Controls whether the service is allowed to execute code from writable memory pages.

**Type**: *Boolean.*

**Default**: `false`.

**Options**:
- **`true`**: Prohibits attempts to create memory mappings that are writable and executable simultaneously, change existing memory mappings to become executable, or map shared memory segments as executable. This restriction is implemented by adding an appropriate system call filter.
- **`false`**: Allows the service to execute code from writable memory pages.

[MemoryDenyWriteExecute](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#MemoryDenyWriteExecute=)

---

### RestrictRealtime

Controls whether the service is allowed to utilize real-time scheduling policies.

**Type**: *Boolean.*

**Default**: `false`.

**Options**:
- **`true`**: Prevents the service from utilizing real-time scheduling policies. Refuses any attempts to enable realtime scheduling in processes of the unit. This restriction prevents access to realtime task scheduling policies such as `SCHED_FIFO`, `SCHED_RR`, or `SCHED_DEADLINE`.
- **`false`**: Allows the service to utilize real-time scheduling policies.

[RestrictRealtime](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RestrictRealtime=)

---

### RestrictSUIDSGID

Controls whether the service is allowed to execute processes with SUID and SGID privileges.

**Type**: *Boolean.*

**Default**: `false`.

**Options**:
- **`true`**: Prevents the service from executing processes with SUID and SGID privileges. Denies any attempts to set the set-user-ID (SUID) or set-group-ID (SGID) bits on files or directories. These bits are used to elevate privileges and allow users to acquire the identity of other users.
- **`false`**: Allows the service to execute processes with SUID and SGID privileges.

[RestrictSUIDSGID](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RestrictSUIDSGID=)

---

### RemoveIPC

Controls whether to remove inter-process communication (IPC) resources associated with the service upon its termination.

**Type**: *Boolean.*

**Default**: `false`

**Options**:
- **`true`**: Removes IPC resources (**System V** and **POSIX IPC** objects) associated with the service upon its termination. This includes IPC objects such as message queues, semaphore sets, and shared memory segments.
- **`false`**: Retains IPC resources associated with the service after its termination.

[RemoveIPC](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RemoveIPC=)

---
 
### SystemCallArchitectures

Specifies the allowed system call architectures for the service to include in system call filter.

**Type**: *Space-separated list of architecture identifiers.*

**Default**: Empty list. No filtering is applied.

**Options**:
- *List of architectures*: Processes of this unit will only be allowed to call native system calls and system calls specific to the architectures specified in the list. e.g. `native`, `x86`, `x86-64` or `arm64` etc.

[SystemCallArchitectures](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#SystemCallArchitectures=)
  
---

### NotifyAccess

Specifies how the service can send service readiness notification signals.

**Type**: *Access specifier string.*

**Default**: `none`.

**Options**:
- `none` (default): No daemon status updates are accepted from the service processes; all status update messages are ignored.
- `main`: Allows sending signals using the main process identifier (PID).
- `exec`: Only service updates sent from any main or control processes originating from one of the `Exec*=` commands are accepted.
- `all`: Allows sending signals using any process identifier (PID).
  
[NotifyAccess](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#NotifyAccess=)

---

# Capabilities 

### AmbientCapabilities

Specifies which capabilities to include in the ambient capability set for the service, which are inherited by all processes within the service.

**Type**: *Space-separated list of capabilities.*

**Default**: Processes inherit ambient capabilities from their parent process or the systemd service manager unless explicitly set.

**Options**:
- *List of capabilities*: Specifies the capabilities that are set as ambient for all processes within the service.
  
This option can be specified multiple times to merge capability sets.

- If capabilities are listed without a prefix, those capabilities are included in the ambient capability set.
- If capabilities are prefixed with "~", all capabilities except those listed are included (inverted effect).
- Assigning the empty string (`""`) resets the ambient capability set to empty, overriding all prior settings.

[AmbientCapabilities](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#AmbientCapabilities=)

---

### CapabilityBoundingSet

Specifies the bounding set of capabilities for the service, limiting the capabilities available to processes within the service.

**Type**: *Space-separated list of capabilities.*

**Default**: If not explicitly specified, the bounding set of capabilities is determined by systemd defaults or the system configuration.

**Options**:
- *List of capabilities*: Specifies the capabilities that are allowed for processes within the service. If capabilities are prefixed with "~", all capabilities except those listed are included (inverted effect).

[CapabilityBoundingSet](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#CapabilityBoundingSet=)

#### Available Options:
**Capability** | **Description**
--- | --
**CAP_AUDIT_CONTROL** | Allows processes to control kernel auditing behavior, including enabling and disabling auditing, and changing audit rules.
**CAP_AUDIT_READ** | Allows processes to read audit log via unicast netlink socket. 
**CAP_AUDIT_WRITE** | Allows processes to write records to kernel auditing log. 
**CAP_BLOCK_SUSPEND** | Allows processes to prevent the system from entering suspend mode.
**CAP_CHOWN** | Allows processes to change the ownership of files.
**CAP_DAC_OVERRIDE** | Allows processes to bypass file read, write, and execute permission checks.
**CAP_DAC_READ_SEARCH** | Allows processes to bypass file read permission checks and directory read and execute permission checks.
**CAP_FOWNER** | Allows processes to bypass permission checks on operations that normally require the filesystem UID of the file to match the calling process's UID.
**CAP_FSETID** | Allows processes to set arbitrary process and file capabilities.
**CAP_IPC_LOCK** | Allows processes to lock memory segments into RAM.
**CAP_IPC_OWNER** | Allows processes to perform various System V IPC operations, such as message queue management and shared memory management.
**CAP_KILL** | Allows processes to send signals to arbitrary processes.
**CAP_LEASE** | Allows processes to establish leases on open files.
**CAP_LINUX_IMMUTABLE** | Allows processes to modify the immutable and append-only flags of files.
**CAP_MAC_ADMIN** | Allows processes to perform MAC configuration changes.
**CAP_MAC_OVERRIDE** | Bypasses Mandatory Access Control (MAC) policies.
**CAP_MKNOD** | Allows processes to create special files using mknod().
**CAP_NET_ADMIN** | Allows processes to perform network administration tasks, such as configuring network interfaces, setting routing tables, etc.
**CAP_NET_BIND_SERVICE** | Allows processes to bind to privileged ports (ports below 1024).
**CAP_NET_BROADCAST** | Allows processes to transmit packets to broadcast addresses.
**CAP_NET_RAW** | Allows processes to use raw and packet sockets.
**CAP_SETGID** | Allows processes to change their GID to any value.
**CAP_SETFCAP** | Allows processes to set any file capabilities.
**CAP_SETPCAP** | Allows processes to set the capabilities of other processes.
**CAP_SETUID** | Allows processes to change their UID to any value.
**CAP_SYS_ADMIN** | Allows processes to perform a range of system administration tasks, such as mounting filesystems, configuring network interfaces, loading kernel modules, etc.
**CAP_SYS_BOOT** | Allows processes to reboot or shut down the system.
**CAP_SYS_CHROOT** | Allows processes to use chroot().
**CAP_SYS_MODULE** | Allows processes to load and unload kernel modules.
**CAP_SYS_NICE** | Allows processes to increase their scheduling priority.
**CAP_SYS_PACCT** | Allows processes to configure process accounting.
**CAP_SYS_PTRACE** | Allows processes to trace arbitrary processes using ptrace().
**CAP_SYS_RAWIO** | Allows processes to perform I/O operations directly to hardware devices.
**CAP_SYS_RESOURCE** | Allows processes to override resource limits.
**CAP_SYS_TIME** | Allows processes to set system time and timers.
**CAP_SYS_TTY_CONFIG** | Allows processes to configure tty devices.
**CAP_WAKE_ALARM** | Allows processes to use the RTC wakeup alarm.

---

# System calls 

### SystemCallFilter

Specifies a system call filter for the service, restricting the types of system calls that processes within the service can make.

**Type**: *Space-separated list of system calls.*

**Default**: If not explicitly specified, there are no restrictions imposed by systemd on system calls.

**Options**:
- *List of system calls*: Specifies the allowed system calls for processes within the service. If the list begins with "~", the effect is inverted, meaning only the listed system calls will result in termination.

Predefined sets of system calls are available, starting with "@" followed by the name of the set.

[SystemCallFilter](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#SystemCallFilter=)

#### Set	Description:
**Filter Set** | **Description**
--- | ---
**@clock** | Allows clock and timer-related system calls, such as clock_gettime, nanosleep, etc. This is essential for time-related operations.
**@cpu-emulation** | Allows CPU emulation-related system calls, typically used by virtualization software.
**@debug** | Allows debug-related system calls, which are often used for debugging purposes and may not be necessary for regular operations.
**@keyring** | Allows keyring-related system calls, which are used for managing security-related keys and keyrings.
**@module** | Allows module-related system calls, which are used for loading and unloading kernel modules. This can be restricted to prevent module loading for security purposes.
**@mount** | Allows mount-related system calls, which are essential for mounting and unmounting filesystems.
**@network** | Allows network-related system calls, which are crucial for networking operations such as socket creation, packet transmission, etc.
**@obsolete** | Allows obsolete system calls, which are no longer in common use and are often deprecated.
**@privileged** | Allows privileged system calls, which typically require elevated privileges or are potentially risky if misused.
**@raw-io** | Allows raw I/O-related system calls, which provide direct access to hardware devices. This can be restricted to prevent unauthorized access to hardware.
**@reboot** | Allows reboot-related system calls, which are necessary for initiating system reboots or shutdowns.
**@swap** | Allows swap-related system calls, which are used for managing swap space.
**@syslog** | Allows syslog-related system calls, which are used for system logging.
**@system-service** | Allows system service-related system calls, which are used for managing system services.
**@timer** | Allows timer-related system calls, which are essential for setting and managing timers.


---

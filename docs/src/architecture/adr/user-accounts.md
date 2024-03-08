<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# User accounts

## Status

Proposed

## Context

Ghaf user accounts follow the Linux model of
- normal users who can login to do use cases (defined shell in `/etc/passwd`)
- system users used to run services but cannot login (`nologin` in `/etc/passwd`)
- super users with administrative privileges (`root`, member of
`sudo`-group)

[Ghaf normal user account is declared in ghaf as
module](https://github.com/tiiuae/ghaf/blob/main/modules/users/accounts.nix).
Also the super user rights (`sudo`-group) are declared for the ghaf
declared users.

Normal user can be personalized - i.e. `username`, `description` -
during installation using the NixOS inherited [`users.users`](https://search.nixos.org/options?channel=23.11&show=users.users)
options.

**The hardening intent on the Ghaf user accounts is:**
- normal users have no `sudo`-rights
- super users has no `root`-rights
  - only rights required for the administrative task
- system users are reduced to minimum based on [subsystem inventory](user-accounts.md#subsystem-user-account-inventory-example)
- user accounts are declared per subsystem (host, guests)

The rights are relaxed only for the Ghaf `debug`-targets to support
development and debugging.

The user account username can be shared between subsystems:
- bootstrapped to the Ghaf installation securely
  - e.g. using `agenix` or FIDO key
- the same secret is not used across subsystems (except debug)
  - applies to both passwordless and password authentication

In other words, a ghaf system installation can have the same username
in different subsystems but each subsystem must have different
authentication secret for the shared username.
Authentication secrets can be accessed from the same FIDO hardware
device or mapped via authentication proxy.

## Subsystem user account inventory example

`ghaf-host` users and groups example on Lenovo X1 Carbon target from
[commit b282ffd](https://github.com/tiiuae/ghaf/commit/b282ffd805bc86ffd789fa1a3d3d54fc9d9d0d20)

```
[root@ghaf-host:/home/ghaf]# for username in $(getent passwd|cut -d ':' -f1); do groups $username; done
root : root
messagebus : messagebus
pulse : pulse audio
polkituser : polkituser
systemd-journal-gateway : systemd-journal-gateway
systemd-coredump : systemd-coredump
systemd-network : systemd-network
systemd-resolve : systemd-resolve
systemd-timesync : systemd-timesync
systemd-oom : systemd-oom
sshd : sshd
rtkit : rtkit
nscd : nscd
microvm : kvm disk audio pulse-access
ghaf : users wheel video ghaf
nixbld1 : nixbld
nixbld2 : nixbld
nixbld3 : nixbld
nixbld4 : nixbld
nixbld5 : nixbld
nixbld6 : nixbld
nixbld7 : nixbld
nixbld8 : nixbld
nixbld9 : nixbld
nixbld10 : nixbld
nixbld11 : nixbld
nixbld12 : nixbld
nixbld13 : nixbld
nixbld14 : nixbld
nixbld15 : nixbld
nixbld16 : nixbld
nixbld17 : nixbld
nixbld18 : nixbld
nixbld19 : nixbld
nixbld20 : nixbld
nixbld21 : nixbld
nixbld22 : nixbld
nixbld23 : nixbld
nixbld24 : nixbld
nixbld25 : nixbld
nixbld26 : nixbld
nixbld27 : nixbld
nixbld28 : nixbld
nixbld29 : nixbld
nixbld30 : nixbld
nixbld31 : nixbld
nixbld32 : nixbld
nobody : nogroup
```

Note: only `ghaf` and `root` have login shell defined. All other
accounts are `nologin`.

Similar analysis to be done for `net-vm` and `gui-vm`

## Consequences

Ghaf user accounts must be refactored from shared `ghaf`-account to
per subsystem declared users.

Findings from removing NixOS declared users - like `nixbld[0-32]` and
`nobody` (`Unprivileged account (don't use!)`) must be linked to this
ADR

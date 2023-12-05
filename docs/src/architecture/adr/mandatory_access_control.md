<!--
SPDX-FileCopyrightText: 2022-2023 TII (SSRC) and the Ghaf contributors

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Mandatory Access Control (MAC)

## Status

Proposed

## Context

To improve Ghaf host and guest security, an improved access control from common
Linux discretionary access control (DAC) is required. This architecture decision
(ADR) record item looks into declaring mandatory access control support on Ghaf
host using (https://apparmor.net/)[AppArmor].

Alternative MAC solutions, like SELinux, exist but are
(https://github.com/NixOS/nix/issues/7850)[not supported on NixOS].

Definition of MAC policies is beyond the scope this ADR.

## Status

Ghaf baseline NixOS has security option support for MAC with AppArmor.
The basic support to enable AppArmor on host is being tested in this draft PR.

The outcome is that AppArmor can be enabled on host-kernel:
```
[root@ghaf-host:~]# aa-status
apparmor module is loaded.
4 profiles are loaded.
4 profiles are in enforce mode.
   /nix/store/9wx7vh5cxgkc0nr7i8dnw3m8g61cs23s-inetutils-2.4/bin/ping
   /nix/store/a83n77qgdfidyr620887qs2ipjb2ndqn-iputils-20221126/bin/ping
   /run/wrappers/bin/ping
   /run/wrappers/wrappers.*/ping
0 profiles are in complain mode.
0 profiles are in kill mode.
0 profiles are in unconfined mode.
0 processes have profiles defined.
0 processes are in enforce mode.
0 processes are in complain mode.
0 processes are unconfined but have a profile defined.
0 processes are in mixed mode.
0 processes are in kill mode.
```

We can conclude that AppArmor can be enabled easily but the relaxed example
policies are not enough.

## Decision

Proposal: Mandatory Access Control could be enabled on `ghaf-host` (and further
on `netvm`) with internal option:

`ghaf.security.mandatory_access_control.enabled = true`

which can be implemented behind Ghaf external API options:

`ghaf.security.host.hardening.enabled = true`
`ghaf.security.netvm.hardening.enabled = true`
`...`

Both Ghaf example subsystems require different set of policies, enforcement and
testing which can be done without risking the Ghaf subsystem development too
early. The option (default) can be set based on the Ghaf subsystem and MAC policy
development maturity.

## Consequences

Enabling the MAC on Ghaf allows policy definition and enforcement.

MAC and policies will introduce issues in development and make issues with
relaxed default security settings visible.

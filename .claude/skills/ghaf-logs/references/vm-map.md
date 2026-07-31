<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# What runs where

Read this when a failure needs attributing to a VM, or when deciding which VM's journal to
open first. Addresses are from a built system's `/etc/hosts`; the generator is
`modules/common/networking/hosts.nix`.

## System VMs

| VM | Address | Responsible for | Look here when |
|---|---|---|---|
| ghaf-host | 192.168.100.2 | hypervisor, `microvm@*` units, PCI passthrough, disks | a VM won't start, passthrough fails, boot/partition trouble |
| net-vm | 192.168.100.1 | physical NIC, DHCP/DNS, firewall, proxy | nothing is reachable, name resolution fails, external access broken |
| gui-vm | 192.168.100.4 | desktop (COSMIC), greetd/login, display, input | no greeter, login fails, screen or input trouble |
| audio-vm | 192.168.100.3 | PipeWire, audio passthrough | no sound, audio device missing |
| admin-vm | 192.168.100.5 | givc admin, aggregated journal (`/var/log/journal/remote/`) | inter-VM control fails; also the cross-VM timeline |

## Application VMs

Start at .101 and vary by profile — the collector enumerates what is actually present.
Typical: business-vm .101, chrome-vm .102, comms-vm .103, flatpak-vm .104, media-vm .105.
Look in an appvm when one application misbehaves but the desktop is otherwise fine.

## Failure signature → where to look

| Signature | Likely VM | Module area |
|---|---|---|
| `greetd`, `pam_`, `cosmic-greeter`, `systemd-homed` | gui-vm | `modules/desktop/graphics/`, `modules/common/services/` |
| `microvm@<name>.service` failed | ghaf-host | `modules/microvm/`, `modules/hardware/passthrough/` |
| `vfio`, `iommu`, PCI bind errors | ghaf-host | `modules/hardware/passthrough/`, hardware definition |
| `givc`, agent/admin connection refused | admin-vm + the peer | `modules/givc/` |
| DHCP, DNS, firewall drops | net-vm | `modules/common/networking/`, `modules/reference/services/` |
| PipeWire, ALSA, no sink | audio-vm | `modules/desktop/`, `modules/hardware/` audio bits |
| journal upload/remote errors | admin-vm + client VM | `modules/common/logging/` |

## Cross-VM dependency order

microVMs come up after ghaf-host, and several depend on net-vm for time and name
resolution. A cascade therefore reads bottom-up: gui-vm failing because a mount was late
because net-vm never came up is one fault, not three. Establish which VM failed *first*
from the manifest timestamps and each VM's own journal before attributing blame.

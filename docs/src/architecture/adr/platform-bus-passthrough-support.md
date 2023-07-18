<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# rust-vmm—Bus Passthrough Support for Rust VMMs

## Status

Proposed, work in progress.


## Context

This ADR is a work-in-progress note for Ghaf bus passthrough implementation that will support rust-vmm-based hypervisors.

> *rust-vmm* is an open-source project that empowers the community to build custom Virtual Machine Monitors (VMMs) and hypervisors. For more information, see <https://github.com/rust-vmm/community>.

It is crucial to have bus devices passthrough support for ARM-based hardware as the bus is mainly used to connect the peripherals. Nowadays, the only hypervisor with some support for Platform bus is QEMU but the code is dated 2013 and not frequently used.

On the other hand, one of the target hardware devices for Ghaf is NVIDIA Orin with an ARM core. To achieve Ghaf's security and hardware isolation goals, devices should support passthrough mode. Production-ready rust-vmm-based hypervisors ([crosvm](https://github.com/google/crosvm), [Firecracker](https://github.com/firecracker-microvm/firecracker), [Cloud Hypervisor](https://www.cloudhypervisor.org/)) do not have support for Platform bus.


## Decision

Implementation of Platform bus passthrough is a base framework for Rust VMM. This will make it possible to use this mode within production-ready rust-vmm-based hypervisors. The main candidate here is crosvm. The necessity to support Platform bus in other hypervisors is subject to discussion. Technically, the Platform bus is rather a simple bus: it manages memory mapping and interrupts. Information about devices is not dynamic but is read from the device tree during the boot stage.

The current status:

| Required Components     |  Status of Readiness     |
|---                      |---                       |
| Host kernel side:       |                          |
| VFIO drivers (to substitute real driver in host kernel) | -/+ |
| Host support for device trees | + |
| Guest kernel side:      |                          |
| Device drivers for passthrough devices | + |
| Guest support for device trees | + |
| Rust VMM side:      | 
| Bus support | Needs to be developed. |
| VMM support for device trees | Rudimental, needs improvement. |
 

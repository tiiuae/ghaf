<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Platform bus passthrough support for RustVMM-based hypervisors

## Status

Proposed, WIP.


## Context

This ADR is WIP notes for Platform bus passthrough implementation for RustVMM-based hypervisors.

Support for Platform bus devices passthrough is important to have for ARM-based hardware because it's the mainly used bus to connect the peripherials. 
Nowdays the only hypervisor that has some support for Platform bus is QEMU, the code is dated 2013 and not frequently used.

On the other hand one of the main hardware platforms for GHAF is NVIDIA Orin, that is ARM and to achieve GHAF's security and hardware isolation goals, devices should be passthroughed to virtual machines.

Production-ready RustVMM-based hypervisors (CrosVM, Firecracker, CloudHypervisor) do not have support for Platform bus, their developers (Google, Amazon, ...) mostly probable are not interested in supporting it because it doesn't align with their business needs.


## Decision

Implement Platform bus passthrough support for RustVMM that is a base framework for RustVMM-based hypervisors.
After that use this support within production-ready RustVMM-based hypervisors. 
The main candidate there is CrosVM, necessity to support Platform bus in  other hypervisors are subject to discuss.

Technically, Platform bus is rather simple bus  -- it manages memory mapping and interrupts. Information about devices is not dynamic, but is read from device tree during the boot stage.

Required components and their existance/use readiness.
- Host kernel side:
 - VFIO drivers (to substitute real driver in host kernel) - +
 - Host support for device trees + 
- Guest kernel side:
  - Device drivers for passthrough devices +
  - Guest support for device trees + 
- RustVMM side:
  - Bus support - Needs to be developed
  - VMM support for device trees -- rudimental, needs improvement. 

## Consequences

GHAF's security and hardware isolation goals reached, platform bus devices are passthroughed to virtual machines.
 

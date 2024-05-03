<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# idsvm-Itrusion Detection System Virtual Machine

## Status

Proposed, partially implemented for development and testing.

*idsvm* reference declaration will be available at [microvm/idsvm.nix]
(https://github.com/tiiuae/ghaf/blob/main/modules/virtualization/microvm/idsvm.nix)

## Context

Ghaf high-level design target is to secure a monolithic OS by modularizing
the OS to networked VMs. The key security target is to detect intrusions by
analyzing the network traffic in the internal network of the OS.

## Decision

The main goal is to have networking entity in Ghaf internal network so that
all network traffic goes via that entity. Traffic then can be analysed to
detect possible intrusions in inter VM communication and outgoing network 
traffic (from VM to internet). This goal is achieved itroducing a dedicated
virtual machine and route all networking from other virtual machines to go
through it. Then it is possible to use various IDS software solutions in 
idsvm to detect possible suspicious network activities.

![Scope!](../../img/idsvm.drawio.png "idsvm Solution")

## Consequences

A dedicated idsvm provides a single checkpoint to detect intrusions
and anomalies in the internal network of the OS and to initiate required
countermeasures.

Routing and analysing the network traffic in separate VM will reduce network
performance.

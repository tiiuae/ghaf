<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Intrusion Detection System Virtual Machine


## Status

Proposed, partially implemented for development and testing.

Intrusion Detection VM (IDS VM) reference declaration will be available at [microvm/idsvm.nix](https://github.com/tiiuae/ghaf/blob/main/modules/microvm/virtualization/microvm/idsvm/idsvm.nix).


## Context

Ghaf's high-level design target is to secure a monolithic OS by modularizing the OS to networked VMs. The key security target is to detect intrusions by analyzing the network traffic in the internal network of the OS.


## Decision

The main goal is to have a networking entity in Ghaf's internal network so that all network traffic goes through that entity. Traffic then can be analyzed to detect possible intrusions in inter VM communication and outgoing network traffic (from VM to the Internet). This goal is achieved by introducing a dedicated VM and routing all networking from other VMs to go through it. Then it is possible to use various IDS software solutions in IDS VM to detect possible suspicious network activities.

![Scope!](../../img/idsvm.drawio.png "IDS VM Solution")


## Consequences

A dedicated IDS VM provides a single checkpoint to detect intrusions and anomalies in the internal network of the OS and to initiate required countermeasures.

Routing and analyzing the network traffic in a separate VM will reduce network performance.


## References

[IDS VM Further Development](/docs/src/ref_impl/idsvm-development.md)

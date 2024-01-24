<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf syncronized time service NTP

## Status

Proposed, work in progress.

## Context

To reduce the data leakage of ghaf all the system components should try to avoid leaking system usage information outside of the system. When Ghaf device is booted up multiple ghaf virtual machines are started roughly at the same time. By default this causes multiple queries to external services such as updating the system clock (NTP). Also NTP query is made whenever a new virtual machine starts so the query would possibly leak a hint to a 3rd party hint that a new virtual machine has been launched.

It is essential for some secure protocols to maintain correct and syncronous time so as for NTP it is not possible just to disable the NTP service completely and rely solely on the system hardware clock to keep everything syncronized. Also some secure software implementations may still use the system time as one component in their pseudo random number generator seed so letting an external party some knowledge about the system approximate startup time may be valuable data for an intruder.

## Decision

Adding a common NTP service to one of the Ghaf common usage virtual machines such as NetVM or possibly some generic utility VM would allow Ghaf system to make one single query to external service to syncronize with the external world clock. Now when the Ghaf NTP service is in sync with external real time it can then serve the correct time to the local virtual machines without making additional queries to external NTP service.

## Consequences

The development scenario reduces the virtual machines external network access and reduces data leakage to 3rd party services. This ADR uses NTP service as an example but similar setup could be added also to other common services such as networked printing service CUPS.

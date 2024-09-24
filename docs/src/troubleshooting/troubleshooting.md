<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Troubleshooting


## Troubleshooting with systemd

Ghaf uses systemd and systemctl to manage services.

This document focuses on troubleshooting common issues with systemd services on Ghaf.

> [!TIP]
> For more information on configurations that can be utilized to enhance the security of a systemd service, see [systemd Service Hardening](/docs/src/ref_impl/systemd-service-config.md).

Since security is the utmost priority, every service has restricted access to resources, which is achieved through hardened service configurations. While these restrictions enhance security, they may also limit the functionality of certain services. If a service fails, it may be necessary to adjust its configuration to restore functionality.

Our current troubleshooting scenarios are the following:

* [Analyzing system logs](./systemd/systemd-analyzer.md)
* [Debugging systemd using systemctl](./systemd/systemctl.md)
* [Inspecting services with systemd-analyze](./systemd/systemd-analyzer.md)
* [Using strace for debugging the initialization sequence](./systemd/strace.md)
* [Early shell access](./systemd/early-shell.md)
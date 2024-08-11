<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# GhafOS: systemd troubleshooting guide

Ghaf OS uses systemd and systemctl to manage services. Since security is the utmost priority, every service has restricted access to resources, which is achieved through hardened service configurations. While these restrictions enhance security, they may also limit the functionality of certain services. If a service fails, it may be necessary to adjust its configuration to restore functionality. This document focuses on troubleshooting common issues with systemd services on Ghaf OS.

1. [Analyze system log](system-log.md)
2. [Use 'systemctl'](systemctl.md)
3. [Use systemd analyzer](systemd-analyzer.md)
4. [Use 'strace' to debug sys call and capability restrictions](strace.md)
5. [Early Shell access](early-shell.md)

<!--
    Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Summary

# Overview

- [About Ghaf](index.md)
- [Features](features/features.md)
- [Architecture](architecture/architecture.md)
  - [Architectural Variants](architecture/variants.md)
  - [Architecture Decision Records](architecture/adr.md)
    - [Minimal Host](architecture/adr/minimal-host.md)
    - [Networking VM](architecture/adr/netvm.md)
    - [Intrusion Detection System VM](architecture/adr/idsvm.md)
    - [Platform Bus for Rust VMM](architecture/adr/platform-bus-passthrough-support.md)
  - [Hardening](architecture/hardening.md)
  - [Secure Boot](architecture/secureboot.md)
  - [Stack](architecture/stack.md)

# For Developers

- [Contributing](appendices/contributing_general.md)
- [Reference Implementations](ref_impl/reference_implementations.md)
  - [Development](ref_impl/development.md)
    - [Build and Run](ref_impl/build_and_run.md)
    - [Running Remote Build on NixOS](ref_impl/remote_build_setup.md)
    - [Installer](ref_impl/installer.md)
    - [Cross-Compilation](ref_impl/cross_compilation.md)
    - [Creating Application VM](ref_impl/creating_appvm.md)
    - [Hardware Configuration](ref_impl/hw-config.md)
    - [Profiles Configuration](ref_impl/profiles-config.md)
    - [labwc Desktop Environment](ref_impl/labwc.md)
    - [IDS VM Further Development](ref_impl/idsvm-development.md)
    - [systemd Service Hardening](ref_impl/systemd-service-config.md)
  - [Troubleshooting](troubleshooting/troubleshooting.md)
    - [Analyzing System Logs](troubleshooting/systemd/system-log.md)
    - [Debugging systemd Using systemctl](troubleshooting/systemd/systemctl.md)
    - [Inspecting Services with systemd-analyze](troubleshooting/systemd/systemd-analyzer.md)
    - [Using strace for Debugging Initialization Sequence](troubleshooting/systemd/strace.md)
    - [Early Shell Access](troubleshooting/systemd/early-shell.md)
  - [Ghaf as Library: Templates](ref_impl/ghaf-based-project.md)
    - [Example Project](ref_impl/example_project.md)
    - [Modules Options](ref_impl/modules_options.md)
- [Technologies](technologies/technologies.md)
    - [Compartmentalization](technologies/compartment.md)
    - [Passthrough](technologies/passthrough.md)
        - [Binding Device to VFIO Driver](technologies/vfio.md)
        - [NVIDIA Jetson AGX Orin: UART Passthrough](technologies/nvidia_agx_pt_uart.md)
        - [NVIDIA Jetson AGX Orin: PCIe Passthrough](technologies/nvidia_agx_pt_pcie.md)
        - [Generic x86: PCIe Passthrough on crosvm](technologies/x86_pcie_crosvm.md)
        - [NVIDIA Jetson: UARTI Passthrough to netvm](technologies/nvidia_uarti_net_vm.md)
        - [Device Tree Overlays for Passthrough](technologies/device_tree_overlays_pt.md)
        - [NVIDIA Jetson: GPU Passthrough](technologies/nvidia_jetson_pt_gpu.md)
    - [Platform Bus Virtualization: NVIDIA BPMP](technologies/nvidia_virtualization_bpmp.md)
    - [Hypervisor Options](technologies/hypervisor_options.md)

# Build System and Supply Chain

- [Continuous Integration and Distribution](scs/ci-cd-system.md)
- [Supply Chain Security](scs/scs.md)
    - [SLSA Framework](scs/slsa-framework.md)
    - [Software Bill of Materials](scs/sbom.md)
    - [Public Key Infrastructure](scs/pki.md)
    - [Security Fix Automation](scs/ghaf-security-fix-automation.md)
- [Release Notes](release_notes/release_notes.md)
    - [Release ghaf-25.03](release_notes/ghaf-25.03.md)
    - [Release ghaf-24.12.4](release_notes/ghaf-24.12.4.md)
    - [Release ghaf-24.12.3](release_notes/ghaf-24.12.3.md)
    - [Release ghaf-24.12.2](release_notes/ghaf-24.12.2.md)
    - [Release ghaf-24.12.1](release_notes/ghaf-24.12.1.md)
    - [Release ghaf-24.12](release_notes/ghaf-24.12.md)
    - [Release ghaf-24.09.4](release_notes/ghaf-24.09.4.md)
    - [Release ghaf-24.09.3](release_notes/ghaf-24.09.3.md)
    - [Release ghaf-24.09.2](release_notes/ghaf-24.09.2.md)
    - [Release ghaf-24.09.1](release_notes/ghaf-24.09.1.md)
    - [Release ghaf-24.09](release_notes/ghaf-24.09.md)
    - [Release ghaf-24.06](release_notes/ghaf-24.06.md)
    - [Release ghaf-24.03](release_notes/ghaf-24.03.md)
    - [Release ghaf-23.12](release_notes/ghaf-23.12.md)
    - [Release ghaf-23.09](release_notes/ghaf-23.09.md)
    - [Release ghaf-23.06](release_notes/ghaf-23.06.md)
    - [Release ghaf-23.05](release_notes/ghaf-23.05.md)

# Ghaf Usage Scenarios

- [Showcases](scenarios/showcases.md)
  - [Running Windows VM on Ghaf](scenarios/run_win_vm.md)
  - [Running Cuttlefish on Ghaf](scenarios/run_cuttlefish.md)

-----------

# Appendices

- [Glossary](appendices/glossary.md)
- [Research Notes](research/research.md)
    - [i.MX 8QM Ethernet Passthrough](research/passthrough/ethernet.md)
    - [System Installation](research/installation.md)

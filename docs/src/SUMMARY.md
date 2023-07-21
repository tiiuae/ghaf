# Summary

# Overview

- [About Ghaf](index.md)
- [Features](features/features.md)
- [Architecture](architecture/architecture.md)
  - [Architectural Variants](architecture/variants.md)
  - [Architecture Decision Records](architecture/adr.md)
    - [Minimal Host](architecture/adr/minimal-host.md)
    - [Networking VM](architecture/adr/netvm.md)
    - [Platform Bus for Rust VMM](architecture/adr/platform-bus-passthrough-support.md)
  - [Stack](architecture/stack.md)

# For Developers

- [Contributing](appendices/contributing_general.md)
- [Reference Implementations](ref_impl/reference_implementations.md)
  - [Development](ref_impl/development.md)
    - [Build and Run](ref_impl/build_and_run.md)
    - [Cross-Compilation](ref_impl/cross_compilation.md)
  - [Ghaf-Based Project](ref_impl/ghaf-based-project.md)
    - [Modules Options](ref_impl/modules_options.md)
- [Technologies](technologies/technologies.md)
    - [Passthrough](technologies/passthrough.md)
        - [NVIDIA Jetson AGX Orin: UART Passthrough](technologies/nvidia_agx_pt_uart.md)
        - [NVIDIA Jetson AGX Orin: PCIe Passthrough](technologies/nvidia_agx_pt_pcie.md)
    - [Hypervisor Options](technologies/hypervisor_options.md)

# Build System and Supply Chain

- [CI/CD System]()
- [Supply Chain Security](scs/scs.md)
    - [SLSA Framework](scs/slsa-framework.md)
    - [Basic Security Measures](scs/basics.md)
    - [Software Bill of Materials](scs/sbom.md)
    - [Public Key Infrastructure](scs/pki.md)
    - [Patch Management Automation](scs/patching-automation.md)
- [Release Notes]()

# Ghaf Usage Scenarios

- [Showcases]()
  - [Running Windows VM on Ghaf](scenarios/run_win_vm.md)
- [Build Your Environment]()

-----------

- [Glossary](appendices/glossary.md)
- [Research Notes](research/research.md)
    - [i.MX 8QM Ethernet Passthrough](research/passthrough/ethernet.md)
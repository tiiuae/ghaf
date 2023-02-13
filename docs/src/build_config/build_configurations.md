<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Build Configurations

Our hardened operating system (OS) targets are build configurations based on NixOS. The canonical URL for the upstream git repository is: [https://github.com/NixOS](https://github.com/NixOS).

Build configurations define our dependencies and configuration changes to packages and build mechanisms of NixOS. If you want to try, see the [reference implementations](../build_config/reference_implementations.md).

## Approach

A build configuration is a target to build our hardened OS for a particular hardware device. Most packages used in a build configuration come from [nixpkgs - NixOS Packages collection](https://github.com/NixOS/nixpkgs).

The upstream first approach means we aim the fix issues by contributing to nixpkgs. At the same time, we get the maintenance support of NixOS community and the benefits of the Nix language on how to build packages and track the origins of packages in the software supply chain security. For more information, see [Supply Chain Security](../scs/scs.md).

NixOS, a Linux OS distribution packaged with Nix, provides us with:
- generic hardware architecture support (``x86-64`` and ``AArch64``);
- declarative and modular mechanism to describe the system;
- Nix packaging language mechanisms:
  - to extend and change packages with [overlays](https://nixos.wiki/wiki/Overlays),
  - to [override](https://nixos.org/guides/nix-pills/override-design-pattern.html) packages.

Even when unmodified upstream is often preferred, even ideal, to ensure timely security updates from upstream — customizations are sometimes required.

### Example

To support a reference board without a vendor board support package (BSP) — bootloader, kernel, device drivers — is often not feasible. With this approach, we can overlay the generic NixOS Linux kernel with the vendor kernel and add a vendor bootloader to build a target image.

Often the vendor BSPs are also open source but sometimes contain unfree binary blobs from the vendor's hardware. Those are handled by allowing ``unfree`` - if the user agrees with the end-user license agreement (EULA). If not, ``unfree`` support can be dropped along with that part of the BSP support.

The same goes with the architectural variants as headless devices or end-user devices differ in terms what kind of virtual machines (VM) they contain. The user needs graphics architecture and VM support for the user interface (UI) whereas a headless device is more like a small server without the UI.


## In This Chapter

- [Reference Implementations](../build_config/reference_implementations.md)
- [Cross Compilation](../build_config/cross_compilation.md)
- [Devices Passthrough](../build_config/passthrough/passthrough.md)
  - [NVIDIA Jetson AGX Orin: UART Passthrough](../build_config/passthrough/nvidia_agx_pt_uart.md)

# Build Configurations

Our hardened operating system (OS) targets are build configurations based on NixOS. The canonical URL for the upstream git repository is: https://github.com/NixOS.

Build configurations define our dependencies and configuration changes to packages and build mechanisms of NixOS. If you want to try and check the details, see [build-configurations](https://github.com/tiiuae/build-configurations/) repository.

## Approach

A build configuration is a target to build our hardened OS for a particular hardware device. The supported development target devices are listed in the [build-configurations](https://github.com/tiiuae/build-configurations/). The packages used in a build configuration comes from [nixpkgs - NixOS Packages collection](https://github.com/NixOS/nixpkgs). Upstream first approach means we aim the fix issues by contributing to nixpkgs. At the same time we get the maintenance support of NixOS community and the benefits of Nix language on how to build packages and track the origins of packages in software supply chain security.

NixOS, a Linux os distribution packaged with Nix, provides us with:
- generic hardware architecture support (``x86_64`` and ``aarch64``)
- declarative and modular mechanism to describe the system
- Nix packaging language mechanisms
  - to extend and change packages with [overlays](https://nixos.wiki/wiki/Overlays)
  - to [override](https://nixos.org/guides/nix-pills/override-design-pattern.html) packages

Even when unmodified upstream are often preferred, even ideal, to ensure timely security updates from upstream - the customizations are sometimes required.

For example, to support a reference board without vendor board support package (BSP) - bootloader, kernel, device drivers - is often not feasible. With this approach we can overlay generic NixOS linux kernel with the vendor kernel and add vendor bootloader to build a target image. Often the vendor BSPs are also open source but sometimes contain unfree binary blobs from the HW vendor. Those are handled by allowing ``unfree`` - if user agrees with the end-user license agreement (EULA). If not, ``unfree`` support can be dropped along with that part of the BSP support. Same goes with the architectural variants - headless devices or end-user devices - differ in terms what kind of virtual machines (VM) they contain. User needs graphics architecture and supporting VMs for the user interface (UI) where a headless device is more like a small server without the UI.

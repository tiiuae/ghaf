<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Approaches to Ghaf System Installation

A hardened system installation covers multiple phases from establishing trust to the installation process. This section describes developing mechanisms to set up a Ghaf system in target hardware.


### Ghaf Initial Approach

The initial Ghaf installation approach to using Ghaf in development and demos is to build target system raw images (`img`) as binary disk images. The process results in an image based on modular and configurable declarations that are repeatably built using NixOS tooling.

In practice, Ghaf disk images are built with:

```
nix build .#package.<hardware-architecture>.<target-device-[release|debug]>
```

which results in disk image:

```
result\nixos.img
```

For information on how to build and run a Ghaf image, see [Build & Run](https://tiiuae.github.io/ghaf/ref_impl/build_and_run.html) for details.

The initial Ghaf installation approach differed from the NixOS installation approach:

 * The key reason in Ghaf was practical: initially, it is simple to write a specific target disk image to a USB boot media or target HW internal persistent media.
 * The NixOS approach is more generic: supporting as many devices as possible. Similar to other Linux distributions like Ubuntu or Fedora.

The development objective of Ghaf is to support a portable secure system that results in a target device-specific small trusted computing base. In practice, this means that Ghaf installations are by design not meant to support a generic Linux kernel with about all the device drivers (modules) out there like Ubuntu or Fedora. Ghaf reference installations are designed and to be developed to support particular (declaratively) hardened host and guest kernels with limited drivers only. The Ghaf approach significantly reduces the size of the trusted computing base as the unneeded modules and kernel parts are not taken into use.


### NixOS Approach

[NixOS installation](https://nixos.org/manual/nixos/stable/#ch-installation) is well documented and thus is only summarized here. The key in the NixOS approach is to have a generic, bootable installation media (`iso`) like any other Linux distribution. As the NixOS installer aims to support as many devices as possible: the installer has a generic kernel (per hardware architecture), hardware recognition script, and generic requirements for system partitioning (`boot` and `root` partitions).

Much of the NixOS installation can be modified interactively during installation either from a graphical installer, manually, or even declaratively. After installation, the whole system can be managed fully declaratively and purely (`flakes`) which is a novel approach compared to other Linux distributions. In practice, you can store your target system declaration in version control (git) to both maintain the system setup and back it up. Ghaf uses this approach for reference system declarations with [flake.nix](https://github.com/tiiuae/ghaf/blob/main/flake.nix).

NixOS usage is popular in cloud system installations. However many cloud providers do not provide NixOS as an option and bare-metal cloud is always not an alternative. For this need, approaches like [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) have been developed. [Using a smart approach with `kexec`](https://numtide.com/blog/we-dont-need-nixos-cloud-images-anymore-2/), one can completely replace cloud provider default Linux options.


### Modular Interactive

Ghaf introduced a modular structure for an [interactive installer](https://tiiuae.github.io/ghaf/ref_impl/installer.html). The initial Ghaf reference installer still uses a raw disk image per target device. In practice, it just writes the raw disk image to the target device's internal persistent memory, for example, NVMe.

The key idea with the modular interactive Ghaf installer is to enable customization of the installer per target device needs and at the same time support further development of the Ghaf graphical installer.

The challenge with the interactive installer is to determine the combination of configurable options, to develop, and test them. Given the Ghaf approach of target device-specific installation [Ghaf Initial Approach](installation.md#ghaf-initial-approach), the requirement for Ghaf a device-specific installer is challenging. Ghaf installer would have to either:

* embed the device-specific installation raw disk image in the installer (current way) which results in a huge installer image
* dynamically build the device-specific installation according to the user's interactive selection
* download a pre-built device-specific raw disk image which could result in a huge number of configurations
* use some combination of generic and specific (a compromise)

None of which seem feasible in the long run. None of these are either Ghaf's objectives in the long run either.

But how to achieve a device-specific secure system installation without getting lost in the generic Linux distro requirements?


### Declarative, Non-Interactive Installation

Now that we already have version control reference device-specific secure system declarations, the question is if we can transfer those into the device installations without requiring a user too many actions that make the installation unnecessarily difficult to implement.

This alone is not a novel idea. Automatic Original Equipment Manufacturer (OEM) installers have been doing this for long. Those are often not declarative but rather scripted guidance to answer questions in generic installers.

The target device-specific disk partitioning has been left to the user in manual installation. Traditionally in generic installers, it is also risk management. A user typically might not want her device disk wiped out without questions asked. Of course, we could let the user know what is about to happen and ask the user for agreement in confirmation before we install it fully automatically. Declarative configurations can handle user preferences. If one wants to change something, it can be changed in the declarations, stored, and shared via version control. [Also including the declarative partitioning](https://github.com/nix-community/disko) that has been tested from within the Ghaf installer.

So, according to the [We don't need NixOS cloud images anymore](https://numtide.com/blog/we-dont-need-nixos-cloud-images-anymore-2/) article, one can think that a secure, virtualized edge device could be handled similarly to cloud images. A simple (even secure) boot and installation supporting media could provide secure network access to the installation target device and then deploy the specific installation from declarations. In practice, a target device can be booted with a USB media (or even network boot) that provides SSH access to the device using an authorized key. After that, one command can be used to install specific secure system configuration automatically. This is used in [Ghaf updates in development](https://tiiuae.github.io/ghaf/ref_impl/development.html) with `nixos-rebuild ... switch` and [was also tested with new (clean) systems](https://github.com/tiiuae/ghaf/pull/340).


---

## Discussion

As of now, the proposed approach declarative non-interactive approach using the example tooling depends on Internet access. Secure system installation will require steps additional to functional system setup. For example, establishing trust and setting up secrets. Many guidelines instruct to setup secrets in an air-gapped environment (without network access) for a reason. Above mentioned tools [do not yet support offline installation](https://github.com/nix-community/disko/issues/408).

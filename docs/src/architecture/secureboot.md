<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Secure Boot

This section describes Secure Boot and how to create secure keys.

The reader is expected to know the fundamentals of UEFI and have a basic understanding of Secure Boot [UEFI specification](https://uefi.org/specifications).

## Enabling Secure Boot

Secure Boot can be enabled on NixOS using [Lanzaboote](https://github.com/nix-community/lanzaboote). Secure Boot is a UEFI feature that only allows trusted operating systems to boot.
Lanzaboote has two components: lzbt and stub. lzbt signs and installs the boot files on the ESP. stub is a UEFI application that loads the kernel and initrd from the ESP.

## Creating Secure Boot Keys

Secure Boot keys can be created with [sbctl](https://github.com/Foxboron/sbctl), a Secure Boot Manager. sbctl is available in Nixpkgs as pkgs.sbctl.

After you installed sbctl or entered a Nix shell, use the following command to create your Secure Boot keys:
```
$ sudo sbctl create-keys
```

Using "sudo sbctl create-keys" command user can create secure keys on the trusted system.

## Current Implementation

For demonstration purposes, we use pre-generated secure keys which are **unsecure** as whoever has keys can break into the system.
Currently, the Secure Boot feature is enabled in debug builds only, since secure key creation requires sudo rights.

### Secure Boot Verification
* For enabling secure boot instructions, see the [Part 2: Enabling Secure Boot](https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md#part-2-enabling-secure-boot) section of the NixOS Secure Boot Quick Start Guide.

* Make sure your Secure Boot is enabled from the BIOS menu.
* Once you boot your system with Secure Boot enabled, enroll keys with the following command:
```
$ sudo sbctl enroll-keys --microsoft
```

Reboot the system to activate Secure Boot in the user mode:

```
$ bootctl status
System:
      Firmware: UEFI 2.70 (Lenovo 0.4720)
 Firmware Arch: x64
   Secure Boot: enabled (user)
  TPM2 Support: yes
  Boot into FW: supported
```
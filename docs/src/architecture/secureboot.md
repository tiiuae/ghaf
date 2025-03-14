<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Secure Boot

This section describes Secure Boot and how to create secure keys.

The reader is expected to know the fundamentals of UEFI and have a basic understanding of Secure Boot [UEFI specification](https://uefi.org/specifications).

## Enabling Secure Boot

TODO: This needs to be filled later with UKI description.

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
* TODO: this needs to be filled.

<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Passwordless Authentication

This section describes Ghaf reference implementation for passwordless authentication for fast identity online (FIDO). The reference implementation has been created with Yubico Yubikeys.
The implementation is modular and configurable - thus enabling also other implementations.

This section describes Yubikey Passwordless Authentication and how to create U2F keys.

The reader is expected to know the fundamentals of [FIDO](https://fidoalliance.org/specifications/), [Yubico](https://www.yubico.com/) and [U2F](https://developers.yubico.com/U2F/).

## Prerequisites for Yubikey Passwordless Authentication

User must have compatible [YubiKey hardware](https://www.yubico.com/products/) to begin with.
The reference implementation has been integrated and tested with Yubikey 5 Series - NFC (USB type A connector).
If another type of Yubikey is used, the device USB vendor and product ids must be updated in the Ghaf target USB device passthrough.

## Creating Yubikey U2F Keys

Yubikey U2F keys can be created with [pamu2fcfg](https://developers.yubico.com/pam-u2f/), a module implements PAM over U2F and FIDO2. pamu2fcfg is available in Nixpkgs as pkgs.pam_u2f.

Use the following command to create your U2F keys for Ghaf gui-vm.
```
$ cd ghaf
$ nix-shell -p pam_u2f
$ pamu2fcfg -u ghaf -o pam://gui-vm | tee -a modules/virtualization/demo-yubikeys/u2f_keys
```

After running above command, there will be green light blinking on the Yubikey and the user must touch the Yubikey to generate the keys.

Next, you can build the Ghaf image and boot it in the target device. After booting, the user authentication in gui-vm is passwordless. When prompted with `Please touch the device." - just touch the Yubikey.

More details about mapping file can found here [central-authorization-mapping](https://github.com/Yubico/pam-u2f#central-authorization-mapping)

## Current Implementation

Since passwordless authentication is mapped with the Yubikey in use and each Yubikey will generate public key that matches the private key inside the device. It is not possible to extract the private key from Yubikey device so it is not possible to use generic debug/demo key to share between users. This is only good thing from security perspective. Such untrusted, shared key cannot be accidentally left on software builds. Each user must have their personal, physical devices that store their private keys. Public keys can be shared in the central authorization mapping (linked from nix store to `/etc/u2f_mappings` during build time). Each user can then authenticate as `ghaf` user in debug-build gui-vms *using their personal Yubikey device*.

Yubikey Passwordless Authentication feature is enabled in debug builds for Ghaf gui-vm using passthrough.
We are using pre-generated public keys which are created using pam2fcfg tool on different machine and it work automatically on gui-vm after the public key part is included in the built image for specific Yubikey.
If user want to register their Yubikey hardware then public key need to generated using pamu2fcfg tool and updated in /etc/u2f_mappings file.

Kindly note that public keys in Ghaf image and/or version control is recommended only for debug and demo purposes. It can be considered secure similar to SSH authorized public keys. Anyone considering more secure approach are expected to follow secure practices - such as generating secrets in air-gapped environments.

### Yubikey Passwordless Authentication Verification
If system is not asking you password in Ghaf guivm for sudo commands anymore then Yubikey Passwordless Authentication feature is working fine.
# Development Secure Boot Keys

⚠️ **WARNING: These keys are for development and testing only.**

These RSA-2048 key pairs (PK, KEK, db) are used for UEFI Secure Boot
during development. They are committed to the repository intentionally
so that any developer can flash and test Secure Boot without setting up
key infrastructure.

**DO NOT use these keys in production.** Anyone with access to the
`db.key` can sign arbitrary EFI binaries that the device will accept as
trusted. Production deployments must use keys generated and stored in a
Hardware Security Module (HSM) or equivalent secure key storage.

## Regenerating

```sh
for name in PK KEK db; do
  openssl req -new -x509 -newkey rsa:2048 -nodes \
    -keyout "$name.key" -out "$name.crt" \
    -subj "/CN=Ghaf Dev Secure Boot $name/" -days 3650
done
```

After regenerating, reflash the device for the new keys to take effect.

## Usage

At flash time, set `SECURE_BOOT_SIGNING_KEY_DIR` to this directory (or
it will be picked up automatically from the NixOS config default):

```sh
SECURE_BOOT_SIGNING_KEY_DIR=$PWD/modules/secureboot/dev-keys \
  sudo ./result/bin/flash-ghaf-host
```

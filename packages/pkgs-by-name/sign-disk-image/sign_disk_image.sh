set -eu -o pipefail
set -x


LOOPDEV=''

function cleanup() {
  set +e
  sudo umount boot
  sudo umount rootfs
  set -e
  if [[ -n "$LOOPDEV" ]]; then
    sudo losetup -d "$LOOPDEV"
  fi
  rmdir boot rootfs
}
trap cleanup SIGINT

if [[ "$1" == clean ]]; then
  cleanup
  exit
fi

if ! type vault; then
  echo "vault binary not found"
  exit 1
fi

if ! type jsign; then
  echo "jsign binary not found"
  exit 1
fi

IMAGE="$1"
if [[ ! -f "$IMAGE" ]]; then
  echo "Argument must be a path to a raw disk image (ex: disk1.raw)"
  echo "zstd compressed output images should be decompressed first"
  exit 1
fi

## Retrieve CA cert and public keys from Vault

export VAULT_ADDR='http://127.0.0.1:8200'
if [[ ! -v VAULT_TOKEN || -z $VAULT_TOKEN ]]; then
  echo "VAULT_TOKEN environment variable is not set. Will not be able to connect to Vault instance"
  exit 1
fi

mkdir keys
KEYDIR=$(realpath ./keys)
pushd "$KEYDIR"
  vault read -field=certificate pki/issuer/new-ca > CA.crt

  vault write -f -field=csr transit/keys/PK/csr > PK.csr
  vault write -f -field=csr transit/keys/KEK/csr > KEK.csr
  vault write -f -field=csr transit/keys/db/csr > db.csr

  vault write -field=certificate pki/issuer/new-ca/sign/root csr="$(cat PK.csr)" common_name="UEFI-PK" ttl="30d" > PK.crt
  vault write -field=certificate pki/issuer/new-ca/sign/root csr="$(cat KEK.csr)" common_name="UEFI-KEK" ttl="30d" > KEK.crt
  vault write -field=certificate pki/issuer/new-ca/sign/root csr="$(cat db.csr)" common_name="UEFI-db" ttl="30d" > db.crt

  # key enroll in Lenovo BIOS only accepts DER format
  openssl x509 -in PK.crt -outform der -out PK.cer
  openssl x509 -in KEK.crt -outform der -out KEK.cer
  openssl x509 -in db.crt -outform der -out db.cer

  echo '' | cat db.crt - CA.crt > dbchain.pem
popd


## Mount disk image partitions

LOOPDEV=$(sudo losetup --show --partscan -f "$IMAGE")
echo "Loop device at $LOOPDEV"

ESP=$(sudo fdisk -l "$LOOPDEV" | grep 'EFI System' | cut -d' ' -f1)
ROOTFS=$(sudo fdisk -x "$LOOPDEV" | grep root | cut -d' ' -f1)
echo "$ESP: ESP partition" 
echo "$ROOTFS: root partition"

mkdir -vp boot rootfs

sudo mount -o loop "$ESP" boot
## Not needed for signing
## could implement sanity checks, for example that UKI cmdline 
## points to the right nix store path
# sudo mount -o loop "$ROOTFS" rootfs


## Sign UKI and systemd loader

cp boot/EFI/BOOT/BOOTX64.efi "$KEYDIR/BOOTX64.efi"
cp boot/EFI/Linux/nixos.efi "$KEYDIR/nixos.efi"

pushd "$KEYDIR"
  jsign remove BOOTX64.efi
  jsign remove nixos.efi
  jsign --storetype HASHICORPVAULT --keystore "$VAULT_ADDR/v1/transit" --storepass "$VAULT_TOKEN" --alias db:1 --certfile db.crt BOOTX64.efi
  jsign --storetype HASHICORPVAULT --keystore "$VAULT_ADDR/v1/transit" --storepass "$VAULT_TOKEN" --alias db:1 --certfile db.crt nixos.efi

  sbverify --cert db.crt BOOTX64.efi
  sbverify --cert db.crt nixos.efi
popd

sudo cp -v "$KEYDIR/BOOTX64.efi" boot/EFI/BOOT/BOOTX64.efi
sudo cp -v "$KEYDIR/nixos.efi" boot/EFI/Linux/nixos.efi

## Copy Secure Boot keys to ESP

sudo mkdir -vp boot/EFI/keys
sudo cp -v "$KEYDIR"/*.cer boot/EFI/keys

cleanup

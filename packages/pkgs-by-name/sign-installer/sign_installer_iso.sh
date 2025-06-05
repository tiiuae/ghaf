set -eu -o pipefail
set -x


function cleanup() {
  set +e
  sudo umount merged
  sudo umount baseroot
  sudo umount iso
  rmdir iso baseroot merged
  sudo rm -r --preserve-root=all upper workdir squashfs-root
  rm pathlist disk1.raw.zst nix-store.squashfs xorriso.cmd
  set -e
}
trap cleanup SIGINT

if [[ "$1" == clean ]]; then
  cleanup
  exit
fi


if [[ ! -v VAULT_TOKEN || -z $VAULT_TOKEN ]]; then
  echo "VAULT_TOKEN environment variable is not set. Will not be able to connect to Vault instance"
  exit 1
fi

export VAULT_ADDR='http://127.0.0.1:8200'
err=0
vault status || err=$?
if [[ $err -ne 0 ]]; then
  echo "Vault is sealed"
  exit 1
fi

NIXBUILD=$(realpath "$1")
if [[ ! -d "$NIXBUILD" ]]; then
  echo "Argument must be the path to the Nix build output (ex: ghaf/result/) that contains ghaf.iso"
  exit 2
fi

# cp "$NIXBUILD/iso/ghaf.iso" "$TMPDIR"
# cp "$NIXBUILD/pathlist" .
cp -v "$NIXBUILD/xorriso.cmd" .

# Extract the installer nix store
mkdir iso
sudo mount -t iso9660 -o ro "$NIXBUILD/iso/ghaf.iso" iso

# Extract the Ghaf disk image from the squashed nix store
DISK_PATH=$(unsquashfs -lc iso/nix-store.squashfs '*ghaf-host-disko-images/disk1.raw.zst' | sed 's|squashfs-root/||')
if [[ -z "$DISK_PATH" ]]; then
  # repart was used in place of disko
  DISK_PATH=$(unsquashfs -lc iso/nix-store.squashfs '*-ghaf-*/ghaf_*.raw.zst' | sed 's|squashfs-root/||')
fi
unsquashfs iso/nix-store.squashfs "$DISK_PATH"

# Decompress the image and sign it
TMPDIR=$(mktemp -d -p .)
zstd -d "squashfs-root/$DISK_PATH" -o "$TMPDIR/disk1.img"
pushd "$TMPDIR"
  sign-disk-image disk1.img
popd
zstd --compress "$TMPDIR/disk1.img" -o disk1.raw.zst

# Packing up...
# Recreate a squashfs with the signed image
mkdir baseroot
sudo mount -t squashfs iso/nix-store.squashfs baseroot
mkdir upper workdir merged
sudo mount -t overlay -o lowerdir=baseroot,upperdir=upper,workdir=workdir overlay merged
sudo cp -v disk1.raw.zst "merged/$DISK_PATH"
mksquashfs merged/* nix-store-mod.squashfs -no-hardlinks -keep-as-directory -all-root -b 1048576 -comp zstd -Xcompression-level 3 -root-mode 0755
mv -v nix-store-mod.squashfs nix-store.squashfs

# Make the iso
xorrisocmd=$(cat xorriso.cmd | awk '{ printf $0 }')
$xorrisocmd -output ghaf-signed.iso

cleanup
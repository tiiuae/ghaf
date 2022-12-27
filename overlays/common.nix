
final: prev: {
  crosvm = final.callPackage ./packages/crosvm { inherit (prev) crosvm; };
  usbutils = final.callPackage ./packages/usbutils {inherit (prev) usbutils; };
  spectrum-rootfs = import ../../spectrum/host/rootfs { };
  spectrum-live = import ../../spectrum/release/live { };
}

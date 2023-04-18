# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  fileSystems."/nix/netvm/store" = {
    device = "none";
    fsType = "tmpfs"; # ramdisk
    # TODO: this mount is used as microvm.nix
    # writableStoreOverlay - so might not need that much
    options = [ "defaults" "size=2G" "mode=755"];
  };
}

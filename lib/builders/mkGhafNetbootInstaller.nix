# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# mkGhafNetbootInstaller - PXE/netboot counterpart to mkGhafInstaller
#
# Builds the same installer as the ISO (same TUI, same disko write, same Secure
# Boot enrollment -- see installer-common.nix) but as netboot artefacts, and
# WITHOUT the ~5.3 GB image embedded. The image is fetched over HTTP at install
# time instead, which is the whole point:
#
#   ISO      ~7 GB per target, ~20 targets, image baked in
#   netboot  ~1.5 GB once for the whole fleet, image chosen at serve time
#
# The kernel/initrd are therefore target-independent; the only per-target
# difference is a URL, so per-target outputs are linkFarms over one shared
# kernel+initrd and cost effectively nothing to add.
#
# Usage:
#   let
#     ghafNetboot = ghaf.builders.mkGhafNetbootInstaller {
#       inherit self;
#       extraModules = installerModules;   # the SAME list the ISO uses
#     };
#   in ghafNetboot { name = "intel-laptop-debug"; }
#
# Output:
#   {
#     name    - e.g. "intel-laptop-debug-netboot-installer"
#     package - directory containing bzImage, initrd, netboot.ipxe
#   }
#
# NOTE: the package is a linkFarm, i.e. symlinks into /nix/store. Copy it with
# `cp -L` / `rsync -L` when staging it onto a TFTP/HTTP root, or the server will
# serve dangling links.
{
  self,
  lib ? self.lib,
  system ? "x86_64-linux",
  extraModules ? [ ],
  # Where the installer fetches ghaf-image.raw.zst / .bmap from. The default
  # defers to iPXE's DHCP-provided ${next-server}, so one built artefact works
  # at any site and no site-specific URL is baked into the repo. A
  # ghaf.image_url= kernel parameter still overrides it at boot.
  imageBaseUrl ? null,
}:
let
  netbootConfig = lib.nixosSystem {
    specialArgs = {
      inherit lib;
    };
    modules = [
      # Everything not about the boot medium. Sharing this with
      # mkGhafInstaller.nix is what keeps the two installers behaving
      # identically -- do not inline installer settings here.
      (import ./installer-common.nix { inherit self system; })
      (
        { modulesPath, ... }:
        {
          imports = [
            "${toString modulesPath}/installer/netboot/netboot-minimal.nix"
          ];

          # The store squashfs measures ~1.45 GiB at the ISO's compression
          # level 3, and it is loaded whole into RAM by iPXE. Trading build
          # time for transfer size is clearly right here: this is sent over the
          # network on every install and unpacked into a resident tmpfs.
          netboot.squashfsCompression = "zstd -Xcompression-level 12";

          # netboot-minimal disables this at mkOverride 70, so a plain
          # definition would NOT win -- it needs mkForce to turn on. Left off
          # deliberately: PXE implies a cable, and the firmware blobs are a
          # large slice of an initrd that has to fit in RAM.
          # hardware.enableRedistributableFirmware = lib.mkForce true;

          # The TUI cannot do anything until the image is reachable, so wait
          # for the network. Netboot only -- the ISO must not gain this, or it
          # stalls on machines with no cable attached.
          systemd.services.ghaf-installer-tui = {
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
          };
        }
        // lib.optionalAttrs (imageBaseUrl != null) {
          ghaf.installer.imageSource = imageBaseUrl;
        }
      )
    ]
    ++ extraModules;
  };

  cfg = netbootConfig.config;
  inherit (netbootConfig) pkgs;

  # One kernel+initrd for every target; only the iPXE script differs.
  sharedBoot = pkgs.linkFarm "ghaf-netboot-boot" [
    {
      name = "bzImage";
      path = "${cfg.system.build.kernel}/${cfg.system.boot.loader.kernelFile}";
    }
    {
      name = "initrd";
      path = "${cfg.system.build.netbootRamdisk}/initrd";
    }
  ];

  # Built from the NixOS-generated script rather than hand-written: it carries
  # the correct init=/nix/store/... path, and getting that wrong is how you end
  # up debugging a stage-1 panic. ${next-server} and ${cmdline} are expanded by
  # iPXE at boot, not by Nix -- hence the '' escapes.
  mkIpxe =
    imageUrl:
    pkgs.writeTextDir "netboot.ipxe" ''
      #!ipxe
      kernel bzImage init=${cfg.system.build.toplevel}/init ${toString cfg.boot.kernelParams} ghaf.image_url=${imageUrl} ''${cmdline}
      initrd initrd
      boot
    '';

  mkGhafNetbootInstaller =
    {
      name,
      # \${next-server} is expanded by iPXE at boot, not by Nix -- in a normal
      # (non-indented) string the escape is \$, whereas the ipxe script below
      # is an indented string and uses ''$.
      imageUrl ? "http://\${next-server}/ghaf-images/${name}",
    }:
    {
      name = "${name}-netboot-installer";
      package = pkgs.linkFarm "${name}-netboot-installer" [
        {
          name = "bzImage";
          path = "${sharedBoot}/bzImage";
        }
        {
          name = "initrd";
          path = "${sharedBoot}/initrd";
        }
        {
          name = "netboot.ipxe";
          path = "${mkIpxe imageUrl}/netboot.ipxe";
        }
      ];
    };
in
mkGhafNetbootInstaller

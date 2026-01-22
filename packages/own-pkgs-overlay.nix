# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  # keep-sorted start skip_lines=1
  flake.overlays.own-pkgs-overlay = final: _prev: {
    audit-rules = final.callPackage ./pkgs-by-name/audit-rules/package.nix { };
    chrome-extensions = final.callPackage ./chrome-extensions { };
    dendrite-pinecone = final.callPackage ./pkgs-by-name/dendrite-pinecone/package.nix { };
    falcon-launcher = final.callPackage ./falcon-launcher/package.nix { };
    flash-script = final.callPackage ./pkgs-by-name/flash-script/package.nix { };
    fleet-desktop = final.callPackage ./pkgs-by-name/fleet-desktop/package.nix { };
    fleet-orbit = final.callPackage ./pkgs-by-name/fleet-orbit/package.nix { };
    gala = final.callPackage ./pkgs-by-name/gala/package.nix { };
    ghaf-build-helper = final.callPackage ./pkgs-by-name/ghaf-build-helper/package.nix { };
    ghaf-installer = final.callPackage ./pkgs-by-name/ghaf-installer/package.nix { };
    ghaf-intro = final.callPackage ./pkgs-by-name/ghaf-intro/package.nix { };
    ghaf-open = final.callPackage ./pkgs-by-name/ghaf-open/package.nix { };
    ghaf-powercontrol = final.callPackage ./ghaf-powercontrol/package.nix { };
    ghaf-vms = final.callPackage ./pkgs-by-name/ghaf-vms/package.nix { };
    hardware-scan = final.callPackage ./pkgs-by-name/hardware-scan/package.nix { };
    make-checks = final.callPackage ./pkgs-by-name/make-checks/package.nix { };
    memsocket = final.callPackage ./pkgs-by-name/memsocket/package.nix { };
    pci-binder = final.callPackage ./pkgs-by-name/pci-binder/package.nix { };
    rtl8126 = final.callPackage ./pkgs-by-name/rtl8126/package.nix { };
    update-docs-depends = final.callPackage ./pkgs-by-name/update-docs-depends/package.nix { };
    user-provision = final.callPackage ./pkgs-by-name/user-provision/package.nix { };
    wait-for-unit = final.callPackage ./pkgs-by-name/wait-for-unit/package.nix { };
    windows-launcher = final.callPackage ./pkgs-by-name/windows-launcher/package.nix { };
  };
  # keep-sorted end
}

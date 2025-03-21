# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  flake.overlays.own-pkgs-overlay = final: _prev: {
    bt-launcher = final.callPackage ./pkgs-by-name/bt-launcher/package.nix { };
    dendrite-pinecone = final.callPackage ./pkgs-by-name/dendrite-pinecone/package.nix { };
    element-gps = final.callPackage ./pkgs-by-name/element-gps/package.nix { };
    element-web = final.callPackage ./pkgs-by-name/element-web/package.nix { };
    flash-script = final.callPackage ./pkgs-by-name/flash-script/package.nix { };
    gala = final.callPackage ./pkgs-by-name/gala/package.nix { };
    ghaf-build-helper = final.callPackage ./pkgs-by-name/ghaf-build-helper/package.nix { };
    ghaf-open = final.callPackage ./pkgs-by-name/ghaf-open/package.nix { };
    ghaf-powercontrol = final.callPackage ./ghaf-powercontrol/package.nix { };
    ghaf-screenshot = final.callPackage ./pkgs-by-name/ghaf-screenshot/package.nix { };
    ghaf-workspace = final.callPackage ./pkgs-by-name/ghaf-workspace/package.nix { };
    globalprotect-openconnect =
      final.callPackage ./pkgs-by-name/globalprotect-openconnect/package.nix
        { };
    hardware-scan = final.callPackage ./pkgs-by-name/hardware-scan/package.nix { };
    ghaf-installer = final.callPackage ./pkgs-by-name/ghaf-installer/package.nix { };
    kernel-hardening-checker =
      final.callPackage ./pkgs-by-name/kernel-hardening-checker/package.nix
        { };
    make-checks = final.callPackage ./pkgs-by-name/make-checks/package.nix { };
    memsocket-app = final.callPackage ./pkgs-by-name/memsocket/package.nix { };
    memsocket-module = final.callPackage ./pkgs-by-name/memsocket/module.nix { };
    open-normal-extension = final.callPackage ./pkgs-by-name/open-normal-extension/package.nix { };
    qemuqmp = final.callPackage ./pkgs-by-name/qemuqmp/package.nix { };
    vhotplug = final.callPackage ./pkgs-by-name/vhotplug/package.nix { };
    vinotify = final.callPackage ./pkgs-by-name/vinotify/package.nix { };
    vsockproxy = final.callPackage ./pkgs-by-name/vsockproxy/package.nix { };
    windows-launcher = final.callPackage ./pkgs-by-name/windows-launcher/package.nix { };
  };
}

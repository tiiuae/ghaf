# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf Introduction - Getting Started guide
#
# Uses the extensions pattern to add the Getting Started app to Chrome VM
# without modifying the Chrome VM's base definition.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.desktop.ghaf-intro;

  introWrapper = pkgs.writeShellApplication {
    name = "ghaf-intro-wrapper";
    runtimeInputs = [
      pkgs.google-chrome
      pkgs.ghaf-intro
    ];
    text = ''
      ${lib.getExe pkgs.google-chrome} \
      --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland \
      --incognito --start-maximized \
      --app=file://${pkgs.ghaf-intro}/index.html
    '';
  };
in
{
  options.ghaf.reference.desktop.ghaf-intro = {
    enable = lib.mkEnableOption "Ghaf introduction guide";
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion =
          (lib.hasAttr "chrome" config.ghaf.virtualization.microvm.appvm.vms)
          && config.ghaf.virtualization.microvm.appvm.vms.chrome.enable;
        message = "Ghaf Introduction requires the Chrome AppVM to be enabled.";
      }
    ];

    # Use extensions to add the Getting Started app to Chrome VM
    # This is applied via NixOS native extendModules
    ghaf.virtualization.microvm.appvm.vms.chrome.extensions = [
      (_: {
        ghaf.appvm.applications = [
          {
            name = "Getting Started";
            description = "Introduction to your Ghaf secure system";
            icon = "security-high";
            packages = [ introWrapper ];
            command = "ghaf-intro-wrapper";
            givcName = "ghaf-intro";
          }
        ];
      })
    ];

    # Ghaf intro autostart config is now provided by guivm-desktop-features module
    # See: modules/desktop/guivm/ghaf-intro.nix

  };
}

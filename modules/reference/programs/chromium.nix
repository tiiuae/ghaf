# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.programs.chromium;
in
{
  options.ghaf.reference.programs.chromium = {
    enable = lib.mkEnableOption "Enable Chromium program settings";
    useZathuraVM = lib.mkEnableOption "Open PDFs in Zathura VM";
  };
  config = lib.mkIf cfg.enable {
    programs.chromium = {
      enable = true;

      # Fix border glitch when going maximised->minimised.
      initialPrefs.browser.custom_chrome_frame = false;

      # Don't use pdf.js, open externally.
      extraOpts."AlwaysOpenPdfExternally" = true;
    };
  };
}

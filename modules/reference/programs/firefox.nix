# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.programs.firefox;
in
{
  _file = ./firefox.nix;

  options.ghaf.reference.programs.firefox = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.firefox.enable;
      description = ''
        Configure Firefox to used the vaapi driver for video decoding.

        Note that this requires disabling the [RDD
        sandbox](https://firefox-source-docs.mozilla.org/dom/ipc/process_model.html#data-decoder-rdd-process).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox.preferences = {
      "media.ffmpeg.vaapi.enabled" = true;
      "media.rdd-ffmpeg.enabled" = true;
      "media.av1.enabled" = true;
      "media.hevc.enabled" = true;
      "dom.media.webcodecs.h265.enabled" = true;
      "gfx.x11-egl.force-enabled" = true;
      "widget.dmabuf.force-enabled" = true;
      "gfx.webrender.all" = true;
      "media.hardware-video-decoding.force-enabled" = true;
    };

    # Disable the RDD sandbox
    # See https://firefox-source-docs.mozilla.org/dom/ipc/process_model.html#data-decoder-rdd-process
    environment.sessionVariables = {
      MOZ_DISABLE_RDD_SANDBOX = "1";
    };
  };
}

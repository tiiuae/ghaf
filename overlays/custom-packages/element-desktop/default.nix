# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes element-desktop
#
{ prev }:
let
  # Source maps are only for browser devtools.
  element-web = prev.runCommand "element-web-without-sourcemaps" { } ''
    cp -r ${prev.element-web} $out
    chmod -R u+w $out
    find $out -name '*.map' -delete
  '';
in
(prev.element-desktop.override { inherit element-web; }).overrideAttrs (old: {
  patches = [ ./element-main.patch ];
  # https://github.com/NixOS/nixpkgs/pull/160462
  installPhase = old.installPhase + ''
    # App VMs have no keyring; without this Element blocks on a consent
    # dialog for its basic_text fallback on first launch.
    wrapProgram $out/bin/element-desktop \
      --add-flags --storage-mode=allow-plaintext \
      --suffix PATH : ${prev.lib.makeBinPath [ prev.xdg-utils ]} \
      --set LIBGL_ALWAYS_SOFTWARE 1 \
      --set ELECTRON_DISABLE_GPU true \
      --set ELECTRON_ENABLE_LOGGING 1
  '';
})

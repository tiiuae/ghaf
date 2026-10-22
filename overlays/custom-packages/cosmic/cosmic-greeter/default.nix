# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-greeter.overrideAttrs (oldAttrs: rec {
  patches = oldAttrs.patches ++ [
    ./0001-Replace-fallback-background-with-Ghaf-default.patch
    ./0002-fix-username-handle-empty-usernames.patch
    ./0003-skip-config-probe-for-locked-homes.patch
    ./0004-locker-focus-password-entry-on-session-lock-focus.patch
  ];
  src =
    (prev.fetchFromGitHub {
      owner = "jannepirskanen";
      repo = "cosmic-greeter";
      rev = "finger_print_resume_after_restart";
      hash = "sha256-U3xx/7vxDtBi/vV+28ecmGfuwmYQj6iY6atJSs39jBE=";
    })
    // {
      tag = "finger_print_resume_after_restart";
    };
  cargoDeps = prev.rustPlatform.fetchCargoVendor {
    inherit src;
    hash = "sha256-SolJzpwXhtziALioyBJt6lhLpiwLN2VnepYCSPxvYyQ=";
  };
})

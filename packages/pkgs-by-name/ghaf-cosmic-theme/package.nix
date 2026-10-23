# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Builds a full COSMIC Theme from a ThemeBuilder RON, as cosmic-settings does.
# Reuses cosmic-settings-daemon's workspace for its vendored cosmic-theme.
{ cosmic-settings-daemon }:
cosmic-settings-daemon.overrideAttrs (oldAttrs: {
  pname = "ghaf-cosmic-theme";

  # After cargoSetupPostPatchHook, which requires Cargo.lock to match the vendor.
  preBuild = ''
    install -Dm0644 ${./main.rs} src/bin/ghaf-cosmic-theme.rs
    sed -i '/^\[dependencies\]$/a ron = "0.12"' Cargo.toml
    sed -i '/^name = "cosmic-settings-daemon"$/,/^]/ s/^ "notify-rust",$/&\n "ron 0.12.2",/' Cargo.lock
  '';

  cargoBuildFlags = [
    "--bin"
    "ghaf-cosmic-theme"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm0755 target/*/release/ghaf-cosmic-theme -t $out/bin
    runHook postInstall
  '';
  postInstall = "";
  postFixup = "";

  meta = oldAttrs.meta // {
    mainProgram = "ghaf-cosmic-theme";
  };
})

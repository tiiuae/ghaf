# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf-cosmic-theme built against cosmic-reader's libcosmic, which still reads
# the v1 theme schema.
# TODO: drop once cosmic-reader moves to a libcosmic with the v2 theme.
{ cosmic-reader }:
cosmic-reader.overrideAttrs (oldAttrs: {
  pname = "ghaf-cosmic-theme-v1";

  # After cargoSetupPostPatchHook, which requires Cargo.lock to match the vendor.
  preBuild = ''
    install -Dm0644 ${./main.rs} ghaf-cosmic-theme/src/main.rs
    cat > ghaf-cosmic-theme/Cargo.toml <<'EOF'
    [package]
    name = "ghaf-cosmic-theme"
    version = "0.1.0"
    edition = "2024"

    [dependencies]
    ron = "0.12"
    cosmic-config = { git = "https://github.com/pop-os/libcosmic.git" }
    cosmic-theme = { git = "https://github.com/pop-os/libcosmic.git" }
    EOF
    printf '\n[workspace]\nmembers = ["ghaf-cosmic-theme"]\n' >> Cargo.toml
    printf '\n[[package]]\nname = "ghaf-cosmic-theme"\nversion = "0.1.0"\ndependencies = [\n "cosmic-config",\n "cosmic-theme",\n "ron",\n]\n' >> Cargo.lock
  '';

  cargoBuildFlags = [
    "-p"
    "ghaf-cosmic-theme"
  ];
  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm0755 target/*/release/ghaf-cosmic-theme $out/bin/ghaf-cosmic-theme-v1
    runHook postInstall
  '';
  postInstall = "";
  postFixup = "";

  meta = oldAttrs.meta // {
    mainProgram = "ghaf-cosmic-theme-v1";
  };
})

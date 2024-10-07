# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  imports = [
    inputs.flake-root.flakeModule
    inputs.treefmt-nix.flakeModule
  ];
  perSystem =
    { config, pkgs, ... }:
    {
      treefmt.config = {
        inherit (config.flake-root) projectRootFile;

        programs = {
          # Nix
          # nix standard formatter according to rfc 166 (https://github.com/NixOS/rfcs/pull/166)
          nixfmt.enable = true;
          nixfmt.package = pkgs.nixfmt-rfc-style;

          deadnix.enable = true; # removes dead nix code https://github.com/astro/deadnix
          statix.enable = true; # prevents use of nix anti-patterns https://github.com/nerdypepper/statix

          # Python
          # Ruff, a Python formatter and linter written in Rust (30x faster than Black).
          ruff.check = true;
          ruff.format = true;

          # Bash
          shellcheck.enable = true; # lints shell scripts https://github.com/koalaman/shellcheck

          # TODO: treefmt claims it changes the files
          # though the files are not in the diff
          # and hence fail in the ci ????
          #toml-sort.enable = true; # TOML formatter
          prettier.enable = true; # JavaScript formatter

        };

        settings = {
          formatter = {
            "statix-check" = {
              command = "${pkgs.statix}/bin/statix";
              options = [ "check" ];
              includes = [ "." ];
            };
          };

          global.excludes = [
            "*.key"
            "*.lock"
            "*.config"
            "*.dts"
            "*.pfx"
            "*.p12"
            "*.crt"
            "*.cer"
            "*.csr"
            "*.der"
            "*.jks"
            "*.keystore"
            "*.pem"
            "*.pkcs12"
            "*.pfx"
            "*.p12"
            "*.pem"
            "*.pkcs7"
            "*.p7b"
            "*.p7c"
            "*.p7r"
            "*.p7m"
            "*.p7s"
            "*.p8"
            "*.png"
            "*.svg"
            "*.license"
            "*.db"
            "*.mp3"
            "*.txt"
            ".version"
            ".nojekyll"
            "*.git*"
            "*.hbs"
            "*.md"
          ];
        };
      };

      formatter = config.treefmt.build.wrapper;
    };
}

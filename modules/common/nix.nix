# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.nix;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  _file = ./nix.nix;

  imports = [
    # Back-compat: these lived under ghaf.development.nix-setup.* until Nix
    # configuration moved out of the development namespace. It was never a
    # development-only concern -- the release profile drives it too -- and the
    # old name made that read as a mistake. Same treatment SSH got when it
    # became ghaf.security.ssh.
    (lib.mkRenamedOptionModule [ "ghaf" "development" "nix-setup" "enable" ] [ "ghaf" "nix" "enable" ])
    (lib.mkRenamedOptionModule
      [ "ghaf" "development" "nix-setup" "nixpkgs" ]
      [ "ghaf" "nix" "nixpkgs" ]
    )
    (lib.mkRenamedOptionModule
      [ "ghaf" "development" "nix-setup" "automatic-gc" "enable" ]
      [ "ghaf" "nix" "automatic-gc" "enable" ]
    )
  ];

  options.ghaf.nix = {
    enable = mkEnableOption "Nix on the target: the daemon, its settings and gc";
    nixpkgs = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a nixpkgs source to pin into `nixPath` and the flake registry.

        Leave null unless the target genuinely needs `nix repl`/`nix-shell` to
        resolve against a pinned tree: the value is the nixpkgs *source*, and
        pinning it makes the whole thing a runtime dependency of the system --
        roughly a 200 MB closure inside the image.
      '';
    };
    automatic-gc.enable = mkEnableOption "automatic garbage collection";
  };

  config.nix = {
    inherit (cfg) enable;
    settings = mkIf cfg.enable {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      keep-outputs = true;
      keep-derivations = true;
    };

    # avoid scenario where the host rootfs gets filled
    # with nixos-rebuild ... switch generated excess
    # generations and becomes unbootable
    gc = {
      automatic = cfg.automatic-gc.enable;
      dates = "daily";
      options = "--delete-older-than 3d";
    };

    # Set the path and registry so that e.g. nix-shell and repl work
    # TODO this should likely be config.nixpkgs, which has the final overlays
    nixPath = lib.mkIf (cfg.enable && cfg.nixpkgs != null) [ "nixpkgs=${cfg.nixpkgs}" ];

    registry = lib.mkIf (cfg.enable && cfg.nixpkgs != null) {
      nixpkgs.to = {
        type = "path";
        path = cfg.nixpkgs;
      };
    };
  };
}

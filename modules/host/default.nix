# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  microvm,
  netvm,
}: {
  lib,
  config,
  pkgs,
  ...
} @ args: let
  cfg = config.ghaf.host.minification;
in
  with lib; {
    options.ghaf.host.minification = with lib; {
      reduceProfile = mkEnableOption "reduced profile";
      disableNetwork = mkEnableOption "disableing of network";
      disableGetty = mkEnableOption "disabling of getty";
      removeNix = mkEnableOption "nix tooling";
      minimalKernelConfig = {
        enable = mkEnableOption "minimal kernel config";
        structuredExtraConfig = mkOption {
          default = types.attrs;
          example = literalExpression ''
            with lib.kernel; {
              SCHED_MUQSS = yes;
            }'';
          description = "Extra config for the kernel. See https://nixos.wiki/wiki/Linux_kernel#Custom_configuration.";
          type = types.attrs;
        };
      };
    };

    # HACK: import other modules with explicit passing of arguments, otherwise import
    # cause infinite recursion.
    config = lib.mkMerge [
      {
        networking.hostName = "ghaf-host";
        system.stateVersion = lib.trivial.release;
      }
      (import ../overlays/custom-packages.nix {inherit lib pkgs;})
      (lib.mkIf cfg.reduceProfile (import ./minimal.nix {inherit pkgs lib;}))
      (lib.mkIf (!cfg.disableNetwork) (import ./networking.nix {}))
      (lib.mkIf cfg.disableGetty {
        # XXX: Incompatable with `services.getty` options.
        systemd.services."getty@".enable = lib.mkForce false;
      })
      (lib.mkIf cfg.removeNix {
        # TODO: Patch raw-efi image build script to support building without relying on
        # image nix tools (replace with packages from nixpkgs).
        nix.enable = false;
      })
      (lib.mkIf cfg.minimalKernelConfig.enable {
        boot.kernelPatches = lib.singleton {
          name = "minimal";
          patch = null;
          extraStructuredConfig = cfg.minimalKernelConfig.structuredExtraConfig;
        };
      })
    ];
  }


# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: {
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      build-users-group = "nixbld";
      trusted-users = [
        "ghaf"
      ];
      trusted-substituters = [
        "https://cache.vedenemo.dev"
        "https://cache.ssrcdevops.tii.ae"
        "https://ghaf-dev.cachix.org"
        "https://cache.nixos.org/"
      ];
      trusted-public-keys = [
        "cache.vedenemo.dev:8NhplARANhClUSWJyLVk4WMyy1Wb4rhmWW2u8AejH9E="
        "cache.ssrcdevops.tii.ae:oOrzj9iCppf+me5/3sN/BxEkp5SaFkHfKTPPZ97xXQk="
        "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
      builders = lib.mkForce [
        "ssh://awsarm aarch64-linux /root/.ssh/id_rsa 8 1 kvm,bechmark,big-parallel,nixos-test"
      ];
    };
    extraOptions = ''
      keep-outputs          = true
      keep-derivations      = true
    '';
  };
}

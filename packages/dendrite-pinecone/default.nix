# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}:
with pkgs;
  buildGo119Module rec {
    pname = "dendrite-pinecone";
    version = "0.9.1";

    src = pkgs.fetchFromGitHub {
      owner = "tiiuae";
      repo = "dendrite";
      rev = "feature/ghaf-integration";
      sha256 = "sha256-UhA9deqWu3ERa08GMGV6/NVHEBZaAdPf7hXQb3GTRcA=";
    };
    subPackages = ["cmd/dendrite-demo-pinecone"];
    # patches = [./turnserver-crendentials-flags.patch];

    vendorHash = "sha256-xMOd4N3hjajpNl9zxJnPrPIJjS292mFthpIQUHWqoYI=";
  }

# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# List of target configurations
#
{
  imports = [
    ./generic-x86_64/flake-module.nix
    ./imx8mp-evk/flake-module.nix
    ./installer/flake-module.nix
    ./laptop/flake-module.nix
    ./laptop-hw-scan/flake-module.nix
    ./microchip-icicle-kit/flake-module.nix
    ./nvidia-jetson-orin/flake-module.nix
    ./vm/flake-module.nix
  ];
}

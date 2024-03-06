# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# List of target configurations
#
{
  imports = [
    ./generic-x86_64/flake-module.nix
    ./imx8qm-mek/flake-module.nix
    ./lenovo-x1-installer/flake-module.nix
    ./lenovo-x1/flake-module.nix
    ./microchip-icicle-kit/flake-module.nix
    ./nvidia-jetson-orin/flake-module.nix
    ./vm/flake-module.nix
  ];
}

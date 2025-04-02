# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf Desktop Experience
#
{ inputs, ... }:
{
  flake.nixosModules = {
    desktop.imports = [
      inputs.self.nixosModules.graphics
      inputs.self.nixosModules.nvidia-gpu
    ];
    graphics.imports = [ ./graphics ];
    nvidia-gpu.imports = [ ./nvidia-gpu ];
  };
}

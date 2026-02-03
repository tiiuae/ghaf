# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
      inputs.self.nixosModules.intel-gpu
      inputs.self.nixosModules.hybrid-gpu
    ];
    graphics.imports = [ ./graphics ];
    nvidia-gpu.imports = [ ./nvidia-gpu ];
    intel-gpu.imports = [ ./intel-gpu ];
    hybrid-gpu.imports = [ ./hybrid-gpu ];

    # GUI VM feature modules (for use with extendModules composition)
    guivm-desktop-features.imports = [ ./guivm ];
  };
}

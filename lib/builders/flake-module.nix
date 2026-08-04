# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for exporting builder functions
{ self, inputs, ... }:
{
  # Export builder functions for downstream consumption
  flake.builders = {
    # ── Unbound forms ─────────────────────────────────────────────────────────
    # The caller supplies self/inputs/lib. Ghaf's own targets/ use these.

    # Unified configuration builder
    mkGhafConfiguration = import ./mkGhafConfiguration.nix;

    # Unified installer builder
    mkGhafInstaller = import ./mkGhafInstaller.nix;

    # Same installer, delivered over the network instead of on an ISO
    mkGhafNetbootInstaller = import ./mkGhafNetbootInstaller.nix;

    # ── Pre-bound forms ───────────────────────────────────────────────────────
    #
    # The same builders, already bound to ghaf's own self, inputs and lib.
    # This is what a downstream should use.
    #
    # Without these, every downstream has to write
    #
    #     inputs.ghaf.builders.mkGhafConfiguration {
    #       self   = inputs.ghaf;
    #       inputs = inputs.ghaf.inputs // { self = inputs.ghaf; };
    #       lib    = inputs.ghaf.lib;
    #     }
    #
    # and there is nothing in the tree that says so. The `// { self = ... }` is
    # the part nobody guesses: `inputs` in a flake-parts module includes `self`
    # (the outputs function receives it), but the `inputs` OUTPUT attribute of a
    # built flake does not -- so a downstream reading `inputs.ghaf.inputs` gets
    # a bundle that is missing exactly the key every ghaf module reads as
    # `inputs.self`. Getting it wrong fails deep inside module evaluation with
    # "attribute 'self' missing" and no hint about the cause.
    #
    # Usage:
    #     cfg = inputs.ghaf.builders.ghafConfiguration {
    #       name = "my-laptop";
    #       system = "x86_64-linux";
    #       profile = "laptop-x86";
    #       hardwareModule = inputs.ghaf.nixosModules.hardware-intel-laptop;
    #       # reach your own flake from inside your modules:
    #       extraSpecialArgs = { mine = self; };
    #     };

    ghafConfiguration = import ./mkGhafConfiguration.nix {
      inherit self inputs;
      inherit (self) lib;
    };

    # Wrappers rather than direct application, because these two take `system`
    # and `extraModules` in the SAME argument set as `self`, and Nix has no
    # partial application of an attrset argument -- binding self here would fix
    # the other two at their defaults.
    ghafInstaller = args: import ./mkGhafInstaller.nix ({ inherit self; } // args);
    ghafNetbootInstaller = args: import ./mkGhafNetbootInstaller.nix ({ inherit self; } // args);
  };
}

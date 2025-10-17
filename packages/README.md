<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Adding packages

When adding a package you should be aware of the main conventions used within Nixpkgs for the formulation of a package attribute set.

The [main pkgs guide](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md) out lines the general conventions for adding a package. To make a package more consumable please follow the [callPackage](https://nixos.org/guides/nix-pills/13-callpackage-design-pattern.html) design pattern when defining a package. This format allows for [override](https://nixos.org/manual/nixpkgs/stable/#sec-pkg-override) customization to the package.

Most packages should reside under the `pkgs-by-name` directory and adhere to the standards defined in Nixpkgs for [pkgs-by-name](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/README.md).

# Adding to overlays

To expose the packages to Ghaf we are currently using the [overlay](https://nixos.org/manual/nixpkgs/stable/#chap-overlays) framework from Nixpkgs. This may change in the future when we move towards a more composable system. Once defined, add your package to `own-pkgs-overlay`, following the calling conventions there.

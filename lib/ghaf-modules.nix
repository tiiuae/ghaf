# SPDX-FileCopyrightText: 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-FileCopyrightText: 2023 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
{ lib }:
let
  inherit (builtins) readFile filter;
  inherit (lib) filesystem hasInfix hasSuffix;

  isDesiredFile = path: hasSuffix ".nix" path && hasInfix "options" (readFile path);
  modulesDirectoryFiles = filesystem.listFilesRecursive ../modules;
in
filter isDesiredFile modulesDirectoryFiles

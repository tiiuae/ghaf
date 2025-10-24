# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib }:
let
  parseSize =
    sizeStr:
    let
      # отделяем цифры от букв
      numStr = lib.strings.removeSuffix (lib.strings.getSuffix 1 sizeStr) sizeStr;
      unit = lib.strings.getSuffix 1 sizeStr;
      num = lib.toInt numStr;
    in
    {
      inherit num unit;
    };

  roundUp = x: builtins.ceil x;

  # tenPercent "64G" -> 7G
  tenPercent =
    sizeStr:
    let
      parsed = parseSize sizeStr;
      perc = roundUp (parsed.num * 0.1);
    in
    "${toString perc}${parsed.unit}";
in
{
  inherit tenPercent;
}

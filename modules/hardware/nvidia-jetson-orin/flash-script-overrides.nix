# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which adds option
# ghaf.nvidia-jetpack.flashScriptOverrides.preFlashCommand
#
{
  config,
  lib,
  ...
}:
with lib; {
  options.ghaf.nvidia-jetpack.flashScriptOverrides = {
    preFlashCommands = mkOption {
      description = "Commands to run before the actual flashing";
      type = types.str;
      default = "";
    };
  };
}

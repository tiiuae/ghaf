# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  satty,
  slurp,
  grim,
  writeShellApplication,
  ...
}:

#write a writeShellApplication to take screenshots using grim sluro and satty
writeShellApplication {
  name = "ghaf-screenshot";
  runtimeInputs = [
    grim
    satty
    slurp
  ];
  text = ''
    dirname="$XDG_PICTURES_DIR/Screenshots"

    # Check if directory exists and create it if it doesn't
    if [ ! -d "$dirname" ]; then
        mkdir -p "$dirname"
    fi

    # Take a screenshot and allow the user to process it before either copying it to the clipboard or saving it to the directory
    # defined some opinionated defaults and this can be reviewed later if we continue to use this after the reselection of the new desktop environment.

    grim -g "$(slurp -c '#ff0000ff' -b '#ffffff80' -w 4)" - | satty --filename - --output-filename "$dirname/screenshot-$(date '+%Y%m%d-%H-%M-%S').png" --save-after-copy
  '';

  meta = {
    description = "ghaf-screenshot";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}

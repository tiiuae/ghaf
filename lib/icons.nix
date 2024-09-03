# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
{
  /*
      *
    Resizes a PNG to fit the given size.

    # Inputs

    `name`

    : Name of the file, this will be included in the output filename.

    `path`

    : Path of the original PNG file to be resized.

    `size`

    : The new size for the image (<height>x<width>).

    # Type

    ```
    resizePNG :: [String] -> [String] -> [String] -> [String]
    ```

    # Example
    :::{.example}
    ## Simple example

    ```nix
    resizePNG "my-icon" ./my-icon-hi-res.png "24x24";
    ```

    :::
  */
  resizePNG =
    name: path: size:
    let
      out =
        pkgs.runCommand "${name}-${size}" { nativeBuildInputs = with pkgs; [ buildPackages.imagemagick ]; }
          ''
            mkdir -p $out
            convert \
              ${path} \
              -resize ${size} \
              $out/${name}.png
          '';
    in
    "${out}/${name}.png";

  /*
      *
    Converts an SVG file to a PNG of a specific size.

    # Inputs

    `name`

    : Name of the file, this will be included in the output filename.

    `path`

    : Path of the original SVG file to be converted.

    `size`

    : The size of the PNG image to be rendered.

    # Type

    ```
    svgToPNG :: [String] -> [String] -> [String] -> [String]
    ```

    # Example
    :::{.example}
    ## Simple example

    ```nix
    svgToPNG "my-icon" ./my-icon.svg "24x24";
    ```

    :::
  */
  svgToPNG =
    name: path: size:
    let
      sizes = builtins.split "x" size;
      width = builtins.head sizes;
      height = builtins.elemAt sizes 2;
      out = pkgs.runCommand "${name}-${size}" { nativeBuildInputs = with pkgs; [ librsvg ]; } ''
        mkdir -p $out
          rsvg-convert ${path} -o $out/${name}.png \
            --width=${width} --height=${height} --keep-aspect-ratio
      '';
    in
    "${out}/${name}.png";
}

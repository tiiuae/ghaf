# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  secctx,
  ...
}:

let
  # Converts a color from an HTML string like "#ff0000" to a vector of floats
  convertColor =
    color:
    let
      r = (lib.trivial.fromHexString (builtins.substring 1 2 color)) / 255.0;
      g = (lib.trivial.fromHexString (builtins.substring 3 2 color)) / 255.0;
      b = (lib.trivial.fromHexString (builtins.substring 5 2 color)) / 255.0;
    in
    "(${toString r}, ${toString g}, ${toString b})";
  # Security context config for Cosmic Compositor
  securityContextConfig = pkgs.writeText "cosmic_security_context" ''
    (
      border_size: ${toString secctx.borderWidth},
      rules:
      [
        ${lib.concatStrings (
          map (rule: ''
            (
              sandbox_engine: "waypipe",
              app_id: "${rule.identifier}",
              border_color: ${convertColor rule.color},
            ),
          '') secctx.rules
        )}
      ],
    )
  '';
in
pkgs.stdenv.mkDerivation rec {
  pname = "ghaf-cosmic-config";
  version = "0.1";

  phases = [
    "unpackPhase"
    "installPhase"
    "postInstall"
  ];

  src = ./.;

  nativeBuildInputs = [ pkgs.yq-go ];

  unpackPhase = ''
    mkdir -p cosmic-unpacked

    # Process the YAML configuration
    for entry in $(yq e 'keys | .[]' $src/cosmic-config.yaml); do
      mkdir -p "cosmic-unpacked/$entry/v1"

      for subentry in $(yq e ".\"$entry\" | keys | .[]" "$src/cosmic-config.yaml"); do
        content=$(yq e --unwrapScalar=false ".\"$entry\".\"$subentry\"" $src/cosmic-config.yaml | grep -vE '^\s*\|')
        echo -ne "$content" > "cosmic-unpacked/$entry/v1/$subentry"
      done
    done
  '';

  installPhase = ''
    mkdir -p $out/share/cosmic
    cp -rf cosmic-unpacked/* $out/share/cosmic/
    rm -rf cosmic-unpacked
    cp ${securityContextConfig} $out/share/cosmic/com.system76.CosmicComp/v1/security_context
  '';

  postInstall = ''
    substituteInPlace $out/share/cosmic/com.system76.CosmicBackground/v1/all \
    --replace "None" "Path(\"${pkgs.ghaf-artwork}/ghaf-desert-sunset.jpg\")"
    substituteInPlace $out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions \
    --replace-fail 'VolumeLower: ""' 'VolumeLower: "pamixer --unmute --decrease 5 && ${pkgs.pulseaudio}/bin/paplay ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"' \
    --replace-fail 'VolumeRaise: ""' 'VolumeRaise: "pamixer --unmute --increase 5 && ${pkgs.pulseaudio}/bin/paplay ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"'
  '';

  meta = with lib; {
    description = "Installs default Ghaf COSMIC configuration";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

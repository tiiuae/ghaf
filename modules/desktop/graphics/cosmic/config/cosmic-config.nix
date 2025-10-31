# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  secctx,
  panelApplets ? {
    left = [ ];
    center = [ ];
    right = [ ];
  },
  extraShortcuts ? [ ],
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

  hasPanelApplets = panelApplets != null && panelApplets != { };

  panelAppletsCenterConfig = lib.optionalString hasPanelApplets (
    pkgs.writeText "plugins_center" ''
      Some([
          ${lib.concatMapStringsSep ",\n  " (a: "\"${a}\"") panelApplets.center}
      ])
    ''
  );

  panelAppletsWingsConfig = lib.optionalString hasPanelApplets (
    pkgs.writeText "plugins_wings" ''
      Some(([
          ${lib.concatMapStringsSep ",\n  " (a: "\"${a}\"") panelApplets.left}
      ], [
          ${lib.concatMapStringsSep ",\n  " (a: "\"${a}\"") panelApplets.right}
      ]))
    ''
  );

  extraShortcutsConfig = lib.optionalString (extraShortcuts != [ ]) (
    pkgs.writeText "extra_shortcuts" ''
      ${lib.concatMapStringsSep ",\n" (s: ''
        (modifiers: [${
          lib.concatMapStringsSep ", " (m: m) s.modifiers
        }], key: "${s.key}"): Spawn("${s.command}")
      '') extraShortcuts}
    ''
  );

  ghaf-volume = pkgs.writeShellApplication {
    name = "ghaf-volume";

    runtimeInputs = [ pkgs.pamixer ];

    text = ''
      AMP_FILE="$HOME/.config/cosmic/com.system76.CosmicAudio/v1/amplification_sink"
      # Enable amplification by default, following COSMIC upstream behavior
      AMP_ENABLED="true"
      LIMIT=150

      if [ -f "$AMP_FILE" ] && [ -s "$AMP_FILE" ]; then
        VALUE=$(tr -d '[:space:]' < "$AMP_FILE")
        if [[ "$VALUE" == "true" || "$VALUE" == "false" ]]; then
          AMP_ENABLED="$VALUE"
        fi
      fi

      change_volume() {
        local dir=$1
        local allow_boost=""
        [[ "$AMP_ENABLED" == "true" ]] && allow_boost="--allow-boost"

        if [[ "$dir" == "up" ]]; then
          pamixer --unmute --increase 5 --set-limit $LIMIT $allow_boost
        elif [[ "$dir" == "down" ]]; then
          pamixer --unmute --decrease 5 --set-limit $LIMIT $allow_boost
        else
          echo "Usage: ghaf-volume {up|down}"
          exit 1
        fi
      }

      change_volume "$1"
    '';
  };
in
pkgs.stdenv.mkDerivation {
  pname = "ghaf-cosmic-config";
  version = "0.2";

  phases = [
    "unpackPhase"
    "installPhase"
    "postInstall"
  ];

  src = ./.;

  nativeBuildInputs = [
    pkgs.yq-go
    pkgs.imagemagick
  ];

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
    # Install configuration files
    mkdir -p $out/share
    cp -r cosmic-unpacked $out/share/cosmic
    rm -rf cosmic-unpacked

    # Install themes
    mkdir -p $out/share/cosmic-themes
    for theme in $src/ghaf-themes/*.ron; do
      install -m0644 "$theme" $out/share/cosmic-themes/
    done
    install -m0644 ${pkgs.ghaf-artwork}/1600px-Ghaf_logo.png $out/share/cosmic-themes/ghaf-dark.png
    magick $out/share/cosmic-themes/ghaf-dark.png -resize 30% $out/share/cosmic-themes/ghaf-dark.png
    ln -s $out/share/cosmic-themes/ghaf-dark.png $out/share/cosmic-themes/ghaf-light.png

    install -Dm0644 ${securityContextConfig} $out/share/cosmic/com.system76.CosmicComp/v1/security_context
  ''
  + ''
    install -Dm0644 ${panelAppletsCenterConfig} $out/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_center
  ''
  + ''
    install -Dm0644 ${panelAppletsWingsConfig} $out/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings
  '';

  postInstall = ''
    substituteInPlace $out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions \
    --replace-fail 'VolumeLower: ""' 'VolumeLower: "${lib.getExe ghaf-volume} down"' \
    --replace-fail 'VolumeRaise: ""' 'VolumeRaise: "${lib.getExe ghaf-volume} up"' \
    --replace-fail 'BrightnessUp: ""' 'BrightnessUp: "${lib.getExe pkgs.brightnessctl} set +5% > /dev/null 2>&1"' \
    --replace-fail 'BrightnessDown: ""' 'BrightnessDown: "${lib.getExe pkgs.brightnessctl} set 5%- > /dev/null 2>&1"'
  ''
  + lib.optionalString (extraShortcuts != [ ]) ''
    if [ -f "$out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/defaults" ]; then
      substituteInPlace "$out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/defaults" \
        --replace "}" "$(cat ${extraShortcutsConfig}) }"
    fi
  '';

  meta = {
    description = "Installs default Ghaf COSMIC configuration";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

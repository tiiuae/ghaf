# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
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
  ''
  + lib.optionalString (panelApplets.center != [ ]) ''
    cp ${panelAppletsCenterConfig} $out/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_center
  ''
  + lib.optionalString (panelApplets.left != [ ] || panelApplets.right != [ ]) ''
    cp ${panelAppletsWingsConfig} $out/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings
  '';

  # TODO: remove audio-volume-change playback when upstream hardcoded path is fixed
  # Also add pipewire (pa-play) to system packages
  # ref https://github.com/pop-os/cosmic-osd/blob/master/src/components/app.rs#L747
  postInstall = ''
    substituteInPlace $out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions \
    --replace-fail 'VolumeLower: ""' 'VolumeLower: "pamixer --unmute --decrease 5"' \
    --replace-fail 'VolumeRaise: ""' 'VolumeRaise: "pamixer --unmute --increase 5"' \
    --replace-fail 'BrightnessUp: ""' 'BrightnessUp: "${lib.getExe pkgs.brightnessctl} set +5% > /dev/null 2>&1"' \
    --replace-fail 'BrightnessDown: ""' 'BrightnessDown: "${lib.getExe pkgs.brightnessctl} set 5%- > /dev/null 2>&1"'
  ''
  + lib.optionalString (extraShortcuts != [ ]) ''
    if [ -f "$out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/defaults" ]; then
      substituteInPlace "$out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/defaults" \
        --replace "}" "$(cat ${extraShortcutsConfig}) }"
    fi
  '';

  meta = with lib; {
    description = "Installs default Ghaf COSMIC configuration";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

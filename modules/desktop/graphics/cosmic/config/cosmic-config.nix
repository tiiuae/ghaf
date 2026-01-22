# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  secctx,
  idle ? {
    screenOffTime = 5 * 60 * 1000;
    suspendOnBattery = 15 * 60 * 1000;
    suspendOnAC = 15 * 60 * 1000;
  },
  topPanelApplets ? {
    left = [ ];
    center = [ ];
    right = [ ];
  },
  bottomPanelApplets ? {
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

  mkRonList = list: "[${lib.concatMapStringsSep ",\n  " (x: "\"${x}\"") list}\n]";

  hasTopPanelApplets = topPanelApplets != null && topPanelApplets != { };

  hasBottomPanelApplets = bottomPanelApplets != null && bottomPanelApplets != { };

  topPanelAppletsCenterConfig = lib.optionalString hasTopPanelApplets (
    pkgs.writeText "plugins_center" ''
      Some(
          ${mkRonList topPanelApplets.center}
      )
    ''
  );

  topPanelAppletsWingsConfig = lib.optionalString hasTopPanelApplets (
    pkgs.writeText "plugins_wings" ''
      Some((
          ${mkRonList topPanelApplets.left}
      ,
          ${mkRonList topPanelApplets.right}
      ))
    ''
  );

  bottomPanelAppletsCenterConfig = lib.optionalString hasBottomPanelApplets (
    pkgs.writeText "plugins_center" ''
      Some(
          ${mkRonList bottomPanelApplets.center}
      )
    ''
  );

  bottomPanelAppletsWingsConfig = lib.optionalString hasBottomPanelApplets (
    pkgs.writeText "plugins_wings" ''
      Some((
          ${mkRonList bottomPanelApplets.left}
      ,
          ${mkRonList bottomPanelApplets.right}
      ))
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

  idleConfig =
    builtins.mapAttrs
      (name: value: pkgs.writeText name (if value == 0 then "None" else "Some(${toString value})"))
      {
        screen_off_time = idle.screenOffTime;
        suspend_on_battery_time = idle.suspendOnBattery;
        suspend_on_ac_time = idle.suspendOnAC;
      };

  ghaf-volume = pkgs.writeShellApplication {
    name = "ghaf-volume";

    runtimeInputs = with pkgs; [
      pulseaudio
      pamixer
    ];

    text = ''
      AMP_FILE="$HOME/.config/cosmic/com.system76.CosmicAudio/v1/amplification_sink"
      VOLUME_CHANGE_SOUND="/run/current-system/sw/share/sounds/freedesktop/stereo/audio-volume-change.oga"

      # Enable amplification by default, following COSMIC upstream behavior
      AMP_ENABLED=true
      LIMIT=150

      # Fast argument parsing
      case "$1" in
        up)   DIR=-i ;;
        down) DIR=-d ;;
        *) echo "Usage: ghaf-volume {up|down}" >&2; exit 1 ;;
      esac

      if [[ -s "$AMP_FILE" ]]; then
        read -r AMP_ENABLED < "$AMP_FILE" || true
      fi

      [[ "$AMP_ENABLED" == "false" ]] && LIMIT=100

      if [[ "$AMP_ENABLED" != "true" ]]; then
        LIMIT=100
        BOOST=""
      else
        BOOST="--allow-boost"
      fi

      CUR_VOLUME=$(pamixer --get-volume)

      pamixer --unmute $DIR 5 --set-limit $LIMIT $BOOST

      # Play sound only if volume changed
      NEW_VOLUME=$(pamixer --get-volume)
      [[ "$CUR_VOLUME" != "$NEW_VOLUME" ]] && paplay "$VOLUME_CHANGE_SOUND"
    '';
  };
in
pkgs.stdenv.mkDerivation {
  pname = "ghaf-cosmic-config";
  version = "0.3";

  phases = [
    "unpackPhase"
    "installPhase"
    "postInstall"
  ];

  src = ./.;

  nativeBuildInputs = [
    pkgs.yq-go
    pkgs.imagemagick
    pkgs.rsync
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
    mkdir -p $out/share/cosmic
    # cp -r cosmic-unpacked $out/share/cosmic
    rsync -a --exclude '*bottom-panel' cosmic-unpacked/ "$out/share/cosmic/"

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
  + lib.concatStringsSep "\n" (
    lib.mapAttrsToList (n: v: ''
      install -Dm0644 ${v} \
        $out/share/cosmic/com.system76.CosmicIdle/v1/${n}
    '') idleConfig
  )
  + ''
    install -Dm0644 ${topPanelAppletsCenterConfig} $out/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_center
    install -Dm0644 ${topPanelAppletsWingsConfig} $out/share/cosmic/com.system76.CosmicPanel.Panel/v1/plugins_wings
  ''
  + ''
    mkdir -p build-layouts/top-panel-and-bottom-dock \
      build-layouts/bottom-panel

    src_layouts=${pkgs.cosmic-initial-setup}/share/cosmic-layouts-unused

    for name in top-panel-and-bottom-dock bottom-panel; do
      install -Dm0644 "$src_layouts/$name/layout.kdl" "build-layouts/$name/layout.kdl"
      install -Dm0644 "$src_layouts/$name/icon.png"   "build-layouts/$name/icon.png"
    done

    for dir in cosmic-unpacked/com.system76.CosmicPanel{,.Panel,.Dock}; do
      cp -rL "$dir" "build-layouts/top-panel-and-bottom-dock/"
    done

    for dir in cosmic-unpacked/*-bottom-panel; do
      base="$(basename "$dir")"
      clean="''${base%-bottom-panel}"
      cp -rL "$dir" "build-layouts/bottom-panel/$clean"
    done

    install -Dm0644 ${topPanelAppletsCenterConfig} build-layouts/top-panel-and-bottom-dock/com.system76.CosmicPanel.Panel/v1/plugins_center
    install -Dm0644 ${topPanelAppletsWingsConfig} build-layouts/top-panel-and-bottom-dock/com.system76.CosmicPanel.Panel/v1/plugins_wings

    install -Dm0644 ${bottomPanelAppletsCenterConfig} build-layouts/bottom-panel/com.system76.CosmicPanel.Panel/v1/plugins_center
    install -Dm0644 ${bottomPanelAppletsWingsConfig} build-layouts/bottom-panel/com.system76.CosmicPanel.Panel/v1/plugins_wings

    # Install layouts
    pushd build-layouts
    find . -type f -exec install -Dm0644 "{}" "$out/share/cosmic-layouts/{}" \;
    popd
  ''
  + ''
    rm -rf cosmic-unpacked build-layouts
  '';

  postInstall = ''
    substituteInPlace $out/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions \
    --replace-fail 'VolumeLower: ""' 'VolumeLower: "${lib.getExe ghaf-volume} down"' \
    --replace-fail 'VolumeRaise: ""' 'VolumeRaise: "${lib.getExe ghaf-volume} up"'
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

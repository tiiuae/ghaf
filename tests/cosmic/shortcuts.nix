# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-free check for ghaf.graphics.cosmic.disabledShortcuts and .systemActions.
# The property most likely to regress is partial override: a binding or action
# that was not named must come through untouched, so those are asserted absent.
{
  self,
  runCommand,
}:
let
  pkgs = import self.inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ self.overlays.default ];
  };

  mkConfig =
    args:
    import ../../modules/desktop/graphics/cosmic/config/cosmic-config.nix (
      {
        inherit (pkgs) lib;
        inherit pkgs;
        secctx = {
          borderWidth = 4;
          rules = [ ];
        };
      }
      // args
    );

  default = mkConfig { };

  disabled = mkConfig {
    disabledShortcuts = [
      "System(AppLibrary)"
      "System(WorkspaceOverview)"
    ];
    systemActions.Launcher = "";
  };

  shortcuts = "share/cosmic/com.system76.CosmicSettings.Shortcuts/v1";
in
runCommand "cosmic-shortcuts" { } ''
  has() {
    grep -qF "$2" "$1" || { echo "FAIL: missing from $1: $2" >&2; exit 1; }
  }
  lacks() {
    grep -qF "$2" "$1" && { echo "FAIL: still in $1: $2" >&2; exit 1; }
    true
  }

  # Defaults: nothing is overridden, so no custom map is written at all.
  test ! -e ${default}/${shortcuts}/custom \
    || { echo "FAIL: custom written with no disabledShortcuts" >&2; exit 1; }
  has ${default}/${shortcuts}/system_actions 'Launcher: "cosmic-launcher"'

  # Every binding of a named action is disabled, including the two forms a
  # by-literal list is most likely to miss: bare Super, and a dedicated key.
  has ${disabled}/${shortcuts}/custom '(modifiers: [Super], key: "a"): Disable,'
  has ${disabled}/${shortcuts}/custom '(modifiers: [Super]): Disable,'
  has ${disabled}/${shortcuts}/custom '(modifiers: [Super], key: "w"): Disable,'
  has ${disabled}/${shortcuts}/custom '(modifiers: [], key: "XF86LaunchA"): Disable,'

  # Partial override: bindings that were not named stay out of the custom map.
  lacks ${disabled}/${shortcuts}/custom 'key: "q"'
  lacks ${disabled}/${shortcuts}/custom 'key: "Tab"'

  # Same for system actions: the named one is neutered, the rest keep working,
  # including ghaf's own volume handlers.
  has ${disabled}/${shortcuts}/system_actions 'Launcher: "",'
  has ${disabled}/${shortcuts}/system_actions 'Terminal: "cosmic-term"'
  has ${disabled}/${shortcuts}/system_actions 'WorkspaceOverview: "cosmic-workspaces"'
  lacks ${disabled}/${shortcuts}/system_actions 'VolumeLower: ""'

  touch "$out"
''

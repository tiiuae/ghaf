# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-free check for ghaf.graphics.cosmic.panels. Asserts the generated `entries`
# lists in the session config and in both selectable layouts, because filtering
# only the session config would let a layout switch restore a removed panel.
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
  none = mkConfig { panels = [ ]; };
  panelOnly = mkConfig { panels = [ "Panel" ]; };

  session = "share/cosmic/com.system76.CosmicPanel/v1/entries";
  topAndDock = "share/cosmic-layouts/top-panel-and-bottom-dock/com.system76.CosmicPanel/v1/entries";
  bottom = "share/cosmic-layouts/bottom-panel/com.system76.CosmicPanel/v1/entries";
in
runCommand "cosmic-panels" { } ''
  has() {
    grep -q "\"$2\"," "$1" || { echo "FAIL: $2 missing from $1" >&2; exit 1; }
  }
  lacks() {
    grep -q "\"$2\"," "$1" && { echo "FAIL: $2 still in $1" >&2; exit 1; }
    true
  }

  # Default: today's behaviour. The bottom-panel layout has only ever had Panel.
  has ${default}/${session} Panel
  has ${default}/${session} Dock
  has ${default}/${topAndDock} Panel
  has ${default}/${topAndDock} Dock
  has ${default}/${bottom} Panel
  lacks ${default}/${bottom} Dock

  # panels = [ ]: no panel anywhere, including both layouts.
  for f in ${none}/${session} ${none}/${topAndDock} ${none}/${bottom}; do
    lacks "$f" Panel
    lacks "$f" Dock
  done

  # panels = [ "Panel" ]: the dock goes, the panel stays.
  for f in ${panelOnly}/${session} ${panelOnly}/${topAndDock} ${panelOnly}/${bottom}; do
    has "$f" Panel
    lacks "$f" Dock
  done

  touch "$out"
''

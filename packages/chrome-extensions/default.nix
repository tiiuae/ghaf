# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  callPackage,
  pkgs,
  google-chrome,
  jq,
  lib,
  stdenvNoCC,
  tinyxxd,
  unzip,
}:

let
  # Helper function for packaging Chrome extensions.
  # It fetches the CRX, extracts its version, and generates an update.xml template.
  mkExtension =
    {
      name,
      id,
      hash,
      version,
      fixedVersion ? true,
    }:
    stdenvNoCC.mkDerivation {
      inherit name version;
      pname = name;
      src = pkgs.fetchurl {
        name = "${name}-${version}.crx";
        url =
          if fixedVersion then
            "https://f6.crx4chrome.com/crx.php?i=${id}&v=${version}"
          else
            "https://clients2.google.com/service/update2/crx?response=redirect"
            + "&os=linux"
            + "&prodchannel=stable"
            + "&prodversion=${google-chrome.version}"
            + "&acceptformat=crx3"
            + "&x=id%3D${id}%26installsource%3Dondemand%26uc";
        postFetch = ''
          if [ ! -f "$out" ] || [ ! -s "$out" ]; then
            echo "Extension (${id}) download failed - file is empty. Ensure destination URL is correct." >&2
            exit 1
          fi
          # Check CRX header
          if ! ${lib.getExe tinyxxd} -l 16 "$out" | grep -qiE '(Cr24|CrX3)'; then
            echo "Extension (${id}) download failed - invalid CRX file (missing Cr24/CrX3 header)." >&2
            exit 1
          fi
        '';
        curlOptsList = [ "-L" ] ++ lib.optional fixedVersion [ "-A 'Mozilla/5.0'" ];
        inherit hash;
      };

      nativeBuildInputs = [
        unzip
        jq
      ];

      dontUnpack = true;

      phases = [ "installPhase" ];

      installPhase = ''
        install -Dm644 $src $out/${id}.crx

        echo "Extracting version from manifest.json"
        set +e
        VERSION=$(unzip -qqp $src manifest.json 2>/dev/null | jq -r .version)
        ec=$?
        set -e

        if [ $ec -gt 1 ] || [ -z "$VERSION" ]; then
          echo "Failed to extract version from ${id}.crx" >&2
          exit 1
        fi

        echo "Detected version: $VERSION"

        echo "Generating update.xml template"
        cat > $out/${id}.xml.template <<EOF
        <?xml version="1.0" encoding="UTF-8"?>
        <gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">
          <app appid="${id}">
            <updatecheck codebase="@UPDATE_BASE_URL@${id}.crx" version="$VERSION"/>
          </app>
        </gupdate>
        EOF
      '';

      passthru = {
        inherit id;
      };

      meta = with lib; {
        description = "Chrome extension ${id}";
        platforms = platforms.all;
      };
    };
in
{
  # Unlike Web Store extensions, this one is built from our own source.
  # We add it here for convenience, so it can be accessed under the same namespace.
  open-normal = callPackage ./open-normal { };

  # Add extensions below using mkExtension { name = "..."; id = "..."; hash = "..."; version = "..."; fixedVersion = true/false; }
  # fixedVersion is set to true by default in order to use crx4chrome.com to fetch pinned extension versions
  # Set fixedVersion = false; to fetch directly from the Chrome Web Store, but note that versions may change without notice.
  # Downgrading should never be done unless a full reinstall of Ghaf is acceptable

  # Example: Session Buddy session and tab manager.
  session-buddy = mkExtension {
    name = "session-buddy";
    id = "edacconmaakjimmfgnblocblbcdcpbko";
    hash = "sha256-iwvPxZe0PfBhgtdVJYj4+4VA+8k/3Pvj20yCoFs07S0=";
    version = "4.1.0";
  };
}

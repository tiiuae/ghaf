# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  callPackage,
  stdenvNoCC,
  fetchurl,
  unzip,
  jq,
  google-chrome,
  lib,
}:

let
  # Helper function for packaging Chrome extensions from the Web Store.
  # It fetches the CRX, extracts its version, and generates an update.xml template.
  mkExtension =
    {
      name,
      id,
      hash,
      version,
    }:
    stdenvNoCC.mkDerivation {
      pname = name;
      inherit version;

      src = fetchurl {
        url =
          "https://clients2.google.com/service/update2/crx?response=redirect"
          + "&prodversion=${google-chrome.version}"
          + "&acceptformat=crx3"
          + "&x=id%3D${id}%26installsource%3Dondemand%26uc";
        postFetch = ''
          if [ ! -f $out ] || [ ! -s $out ]; then
            echo "Extension (${id}) download failed - file is empty. Ensure destination URL is correct." >&2
            exit 1
          fi
        '';
        curlOptsList = [ "-L" ];
        name = "${id}";
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

  # Example: Session Buddy session and tab manager.
  # Hash must be updated manually when the extension is updated upstream.
  # Version is optional and doesn't affect the build, but is useful for reference.
  session-buddy = mkExtension {
    name = "session-buddy";
    id = "edacconmaakjimmfgnblocblbcdcpbko";
    hash = "sha256-iwvPxZe0PfBhgtdVJYj4+4VA+8k/3Pvj20yCoFs07S0=";
    version = "4.1.0";
  };

  # Add more extensions below using mkExtension { name = "..."; id = "..."; hash = "..."; version = "...";  }
}

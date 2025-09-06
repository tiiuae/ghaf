# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenvNoCC,
  makeWrapper,
  coreutils,
  chromium,
}:
let
  # Extension ID is based on the public key derived from the private key,
  # so it is constant as long as the key is not changed
  # Here we have pre-computed it according to Chrome's algorithm
  extensionId = "nbghaffnmohnlmojmdnbenakkmddkaik";
  # Not the best practice to have private keys in the repo,
  # but this is a throwaway key just to keep the extension ID constant
  keyPem = builtins.toFile "key.pem" ''
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDOxAqT0m6d2zaT
    ctGIDGQd0QyXXWW70Qa2zCyGBHCmplDKVuoHvZDNX6M3fyfxuBVmEhigJHaxeHYn
    aeC3Bp9oVRf8egqq+cfhf7qUUyjQFRNHt3NTp7kTicfowVcJnx5+1W6vOGK/ArRl
    mv4r/XDSUXrOqBcHRee0ev3hb72DwmQcdBC4WJjbxOU60EDe6lEvqUVk2JPmHnvt
    cc4nf5zUksH2U2aZt0EZNz1qV5kELk/Cr4xU85Kx01BfVCIFYIBm2qYqwonwUKxl
    6+Lntq4QoOc6E8W30QWAMl7wOhXQ0tttF1qetnKDdZG4RUOMfjynMGM0FOgpSps4
    U+939VS7AgMBAAECggEADpY/Bsm4OxO9iG53wMjbAU1/vWf95t+qwRerZnMGvYML
    PRMfpJcnkY2XNrGWUFPD0rUhHp8j7oZIk6RBEbh6Y4JpVEsJ2KERjGOV9qPdQ7zQ
    5OTY0oSJJos4Wr/VE50xqhIFon/wW3hl4KssFk9ld7j+2Hh8U2uHmrB4m8Bl1tct
    2jTTALjTyeHSX7Wyucvc2WSiJRAYYXd/kntZF0aOLtWiS/7uHKiNf1PY3Eb1xXrj
    HBf4Kj1Tc8nLUD+Z3mhr0SrsRWKNheHva53zZDY0J9oS7Sus2SPr5Dlm+3k9LKCv
    entd7m3iszQIC2tzAHSK79Jt6NfIWlm3XLatkhmKyQKBgQD9j9ir/kwbvWGeF2Jt
    qTpkXHWoPaVS1U6g9ewAu4OkWTA8Gw+hUi3YYQ4mb/U2z0M9CoYc9L/xuLxAXBMp
    H6v+sc4RIoyn+ywvSEmUzl//Z0Zimmdukh0TEsOnHOWaJMDphFi7MfwdRGgLR+eD
    iw4gyzyfK094uNwwKELrqk0TeQKBgQDQwQEYZck9/HC37Ia+qwKHLjO49yBZQjVD
    Fwg/nTonFNLG4W0DyVdKjLtddNDXuzxEahY1JLU1xY4oA1BbwjmaHsN4arHN48lc
    nG/V4ho58KD831CJfPpKu8OITD6MdNjTXRyd8OeQBBJbMr2SKkU0HlHaY22Gk4EC
    sgwSPUaI0wKBgFmq7Oyl2TRWHJdTnbM6DTRAnjsI0dYhKNUzImp/5WXRRIV87GIY
    Na43ZFGjdgwT76s+dX737okE003PQddhI+nF5yGYHjWpVU7DOYIuGTSwyOtFvx4S
    /cUo9Ze7WFbSeIYcD2TjoEyZTFHw86ZJHo3qUV3Yaxo+BV/iXQgKCYfBAoGBAKts
    InMfep8tQn62e3vtQDkzxoN4ZBcIGGbMbhiXCx72qZNpoDTAzK7KXD4FZE4TUg04
    NJ5VU30hinfvKLkBCH44Dvo+W14gVMV5LRks/65enESrOR5+A6cFAy9UtPRwK3F9
    /7bvEaigv1Yml6eEkKmY0EyO42zkicdl4CXGLbrDAoGBAM3O2l0gNsilufZuk2B4
    k70vjV0ono2HVxXunb7J4c2451D/7FjqR+TIFQX0c+h1hncwCKu/i0Z/eUv+8bJE
    Go1MYYUQU6FrwS96poThSKxrqnWbe2MJcHn/p3fH5gsSe2i9QE0rwwHMFJsTgKaT
    pLcamACvWXqkIqTNRde4iLk9
    -----END PRIVATE KEY-----
  '';
in
stdenvNoCC.mkDerivation {
  name = "open-normal-extension";

  src = ./open-normal-extension;
  key = keyPem;
  updateXml = ./update.xml;

  nativeBuildInputs = [
    makeWrapper
    chromium
    coreutils
  ];

  phases = [
    "installPhase"
  ];

  installPhase = ''
    workdir="$out/tmp"
    mkdir -p "$workdir" "$out/share"

    # Patch shebangs + wrap script
    cp "$src/open_normal.sh" "$out/open_normal.sh"
    patchShebangs --host $out/open_normal.sh
    wrapProgram "$out/open_normal.sh" \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]}

    cp "$out/open_normal.sh" "$workdir/open_normal.sh"
    cp -r "$src"/*.json "$workdir"
    cp -r "$src"/*.js "$workdir"

    chmod a+x "$workdir/open_normal.sh"

    # Patch
    substituteInPlace "$workdir/fi.ssrc.open_normal.json" \
      --replace-fail "PATH_HERE" "$out/open_normal.sh" \
      --replace-fail "EXTENSION_ID" "${extensionId}"

    # Remove comments
    cp "$updateXml" "$out/share/update.xml"
    sed -i '/^\s*\/\//d' \
      "$workdir/fi.ssrc.open_normal.json" \
      "$workdir/manifest.json" \
      "$out/share/update.xml"

    # Pack extension
    chromium \
      --headless \
      --disable-gpu \
      --no-sandbox \
      --disable-software-rasterizer \
      --disable-background-networking \
      --disable-background-timer-throttling \
      --disable-breakpad \
      --disable-crash-reporter \
      --disable-crashpad-for-testing \
      --disable-default-apps \
      --disable-dev-shm-usage \
      --disable-logging \
      --no-first-run \
      --no-default-browser-check \
      --pack-extension="$workdir" \
      --pack-extension-key="$key"

    if [ ! -e "$out/tmp.crx" ]; then
      echo "ERROR: Failed to pack extension"
      echo "Contents of $workdir >>>"
      ls -l "$workdir" || true
      exit 1
    fi

    # Install
    mv "$out/tmp.crx" "$out/share/open-normal-extension.crx"
    cp -r "$workdir"/* "$out"
    rm -rf "$workdir"
  '';

  passthru = {
    id = "${extensionId}";
  };

  meta = {
    description = "Browser extension for trusted browser to launch normal browser";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}

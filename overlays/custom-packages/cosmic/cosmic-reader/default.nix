# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Reduce closure size by disabling tesseract mupdf feature
# Saves approx 900 MB
{ prev }:
prev.cosmic-reader.overrideAttrs (oldAttrs: {
  buildInputs = builtins.filter (
    p: (p.pname or "") != "tesseract" && (p.pname or "") != "leptonica"
  ) (oldAttrs.buildInputs or [ ]);
  postPatch = (oldAttrs.postPatch or "") + ''
        substituteInPlace Cargo.toml \
          --replace-fail \
            'git = "https://github.com/messense/mupdf-rs"
    optional = true' \
            'git = "https://github.com/messense/mupdf-rs"
    optional = true
    default-features = false
    features = ["js","xps","svg","cbz","img","html","epub","system-fonts","brotli","docx-output"]'
  ''; # Here we exclude 'tesseract' on purpose to reduce closure size
})

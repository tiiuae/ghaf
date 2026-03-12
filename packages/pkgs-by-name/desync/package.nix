# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "desync";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "folbricht";
    repo = "desync";
    tag = "v${version}";
    hash = "sha256-aRxWq9gGfglfBixS7xOoj8r29rJRAfGj4ydcSFf/7P0=";
  };

  vendorHash = "sha256-ywID0txn7L6+QkYNvGvO5DTsDQBZLU+pGwNd3q7kLKI=";

  # Skip tests that require network access or special fixtures
  doCheck = false;

  meta = {
    description = "Content-addressed binary diff tool (casync alternative in Go)";
    homepage = "https://github.com/folbricht/desync";
    license = lib.licenses.bsd3;
    mainProgram = "desync";
  };
}

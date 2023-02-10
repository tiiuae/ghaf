# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  runCommandNoCC,
  mdbook,
}:
runCommandNoCC "ghaf-doc"
{
  nativeBuildInputs = [mdbook];
} ''
  ${mdbook}/bin/mdbook build -d $out ${./.}
''

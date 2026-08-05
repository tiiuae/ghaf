# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-free regression check for fss-verify-classifier.sh: the same case table
# logging-fss runs, against the file in the repository, in seconds.
{
  runCommand,
  callPackage,
}:
let
  cases = callPackage ./test_scripts/fss-classifier-cases.nix { };
in
runCommand "fss-classifier-unit" { } ''
  ${cases}/bin/fss-classifier-cases ${../../modules/common/logging/fss-verify-classifier.sh}
  touch "$out"
''

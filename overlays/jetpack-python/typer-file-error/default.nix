# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# The setuptools pin makes typer a cache miss; its test_file_error then fails
# because rich 15 elides the file name in the narrow error panel.
_pyFinal: pyPrev: {
  typer = pyPrev.typer.overridePythonAttrs (oldAttrs: {
    disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_file_error" ];
  });
}

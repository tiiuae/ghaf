# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_pyFinal: pyPrev: {
  # TODO: drop once the locked filelock includes https://github.com/tox-dev/filelock/pull/865.
  filelock = pyPrev.filelock.overridePythonAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./doorway-cleanup-test.patch ];
  });
}

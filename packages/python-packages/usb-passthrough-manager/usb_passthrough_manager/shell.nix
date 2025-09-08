# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = [
    pkgs.python311
    pkgs.python311Packages.pyqt6
    pkgs.python311Packages.virtualenv
    pkgs.qt6.qtbase
    pkgs.qt6.qtwayland
    pkgs.python311Packages.setuptools
    pkgs.python311Packages.wheel
    pkgs.python311Packages.build
  ];

  shellHook = ''
    # Create a venv that can see Nix-installed packages (PyQt6)
    if [ ! -d .venv ]; then
      virtualenv --system-site-packages .venv
    fi
    source .venv/bin/activate

    # (Optional) keep deps under Nix; don't let pip pull another PyQt6 wheel
    # Remove PyQt6 from pyproject deps OR install with --no-deps:
    echo "Tip: use 'pip install -e . --no-deps' to avoid pulling PyQt6 from PyPI"

    # Tell Qt where plugins live (platforms/, imageformats/, etc.)
    export QT_PLUGIN_PATH=${pkgs.qt6.qtbase}/lib/qt-6/plugins:${pkgs.qt6.qtwayland}/lib/qt-6/plugins

    # You can force platform while testing (comment one out as needed)
    #export QT_QPA_PLATFORM=wayland
    # export QT_QPA_PLATFORM=xcb

    echo "Welcome to your Python dev env."
    echo "Now you can run:"
    echo "  pip install -e . --no-deps"
    echo "  QT_DEBUG_PLUGINS=1 upm_app"
  '';
}

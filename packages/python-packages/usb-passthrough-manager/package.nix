# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  buildPythonApplication,
  wheel,
  setuptools,
  qt5,
  pyqt5,
  libsForQt5,
}:
buildPythonApplication {
  pname = "usb_passthrough_manager";
  version = "0.0.1";
  src = ./usb_passthrough_manager;
  pyproject = true;

  nativeBuildInputs = [
    setuptools
    wheel
    libsForQt5.wrapQtAppsHook
  ];

  propagatedBuildInputs = [
    pyqt5
    qt5.qtbase
    qt5.qtwayland
  ];

  buildInputs = [
    qt5.qtbase
    qt5.qtwayland
  ];
}

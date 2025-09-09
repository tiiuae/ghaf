# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  buildPythonApplication,
  wheel,
  setuptools,
  qt6,
  pyqt6,
#qt6Packages,
}:
buildPythonApplication {
  pname = "usb_passthrough_manager";
  version = "0.0.1";
  src = ./usb_passthrough_manager;
  pyproject = true;

  nativeBuildInputs = [
    setuptools
    wheel
    qt6.wrapQtAppsHook
  ];

  propagatedBuildInputs = [
    pyqt6
    qt6.qtbase
    qt6.qtwayland
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtwayland
  ];

  postFixup = ''
    wrapQtApp $out/bin/upm_app --prefix QT_PLUGIN_PATH : ${qt6.qtbase}/lib/qt-6/plugins:{qt6.qtwayland}/lib/qt-6/plugins
    wrapQtApp $out/bin/upm_service --prefix QT_PLUGIN_PATH : ${qt6.qtbase}/lib/qt-6/plugins:{qt6.qtwayland}/lib/qt-6/plugins
  '';
}

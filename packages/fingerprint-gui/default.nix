{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  meson,
  ninja,
  cmake,
  glib,
  nss,
  pam,
  pixman,
  xorg,
  libfakekey,
  libusb1,
  qt5,
  libsForQt5,
  pkg-config,
}:
let
  libfprint_old = stdenv.mkDerivation {
    pname = "libfprint-1";
    version = "0.8.2";
    src = fetchurl {
      url = "http://deb.debian.org/debian/pool/main/libf/libfprint/libfprint_0.8.2.orig.tar.xz";
      hash = "sha256-+iVL3j0jTGS8VUPIbc3yBVKLdUGyUGpkAXsIYUJnhC4=";
    };
    nativeBuildInputs = [
      meson
      ninja
      pkg-config
    ];
    buildInputs = [
      glib
      libusb1
      nss
      pixman
      xorg.libX11
    ];
    mesonFlags = [
      "-Dudev_rules_dir=${placeholder "out"}/lib/udev/rules.d"
      # Include virtual drivers for fprintd tests
      "-Ddrivers=all"
      "-Ddoc=false"
      "-Dx11-examples=false"
    ];
    postPatch = ''
      sed -i "s,/bin/echo,echo," libfprint/meson.build
    '';
  };
in
stdenv.mkDerivation {
  pname = "fingerprint-gui";
  version = "1.09-git-2021.06.29";
  src = fetchFromGitHub {
    owner = "RogueScholar";
    repo = "fingerprint-gui";
    rev = "85a376e908b1daee0e3e0760574b19dccd84afd4";
    hash = "sha256-Pjc0iO6L28/8/nkmWYLuz9ISmrc4Xb8T1d9c93KQ7FQ=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    qt5.wrapQtAppsHook
  ];
  buildInputs = [
    libfakekey
    libusb1
    libfprint_old
    pam
    qt5.qtbase
    qt5.qtx11extras
    qt5.qttools
    libsForQt5.qca
    libsForQt5.polkit-qt
    xorg.libXtst
  ];

  postPatch = ''
    # cmake install expect this file
    cp LICENSES/GPL-3.0-or-later.txt COPYING

    # cmake try install into /var by absolute path
    sed -i -e 's,/var,''${CMAKE_INSTALL_PREFIX}/var,' CMakeLists.txt

    # Install of upek stuff is broken, anyway we don't use upek
    sed -i -e 's,add_subdirectory(upek),,' CMakeLists.txt

    # FIXME: This `bin/fingerprint-polkit-agent/fingerprint-polkit-agent.desktop` need to be properly installed
    #        Right now just cut it out, to quickfix package
    sed -i -e '/autostart/d' bin/CMakeLists.txt
    sed -i -e '/92-fingerprint-gui-uinput/d' bin/CMakeLists.txt
  '';

  meta = with lib; {
    description = "Fingerprint tool";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

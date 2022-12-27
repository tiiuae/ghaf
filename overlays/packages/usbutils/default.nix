{ usbutils, lib, stdenv, libudev-zero, ... }:

  usbutils.overrideAttrs ( prevAttrs: {
    buildInputs = prevAttrs.buildInputs ++ [ libudev-zero ];
})

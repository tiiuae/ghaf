# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This is generic overlay to override stuff inside Python package collections,
# and can be applied to various different versions of Python.
#
{
  final,
  python,
}:
python.override {
  packageOverrides = _finalPy: prevPy: {
    # Make dbus-python cross-compileable
    # https://github.com/NixOS/nixpkgs/issues/309395
    dbus-python = prevPy.dbus-python.overrideAttrs (_finalAttrs: prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [final.dbus];
    });
  };
}

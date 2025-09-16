# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  setuptools,
  ldap3,
  gssapi,
  lib,
}:
buildPythonApplication {
  pname = "ldap-query";
  version = "0.1";

  pyproject = true;
  build-system = [ setuptools ];

  src = ./ldap-query;

  propagatedBuildInputs = [
    ldap3
    gssapi
  ];

  doCheck = false;

  meta = {
    description = "A simple LDAP query tool";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "ldap-query";
  };
}

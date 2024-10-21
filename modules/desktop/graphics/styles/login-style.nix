# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Ghaf login screen style
{
  pkgs,
  ...
}:
pkgs.writeText "ghaf-login.css" ''
  window {
      background: rgba(18, 18, 18, 1);
      color: #fff;
  }
  button {
      box-shadow: none;
      border-radius: 5px;
      border: 1px solid rgba(255, 255, 255, 0.09);
      background: rgba(255, 255, 255, 0.06);
  }
  entry {
      background-color: rgba (43, 43, 43, 1);
      border: 1px solid rgba(46, 46, 46, 1);
      color: #eee;
  }
  entry:focus {
      box-shadow: none;
      border: 1px solid rgba(223, 92, 55, 1);
  }
''

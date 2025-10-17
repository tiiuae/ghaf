# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Ghaf app launcher style
{
  writeText,
  ...
}:
writeText "ghaf-launcher.css" ''
  /* Example configuration from: https://github.com/nwg-piotr/nwg-drawer/blob/main/drawer.css */
  window {
      background-color: #121212;
      color: #fff;
  }

  /* search entry */
  entry {
      background-color: rgba (43, 43, 43, 1);
      border: 1px solid rgba(46, 46, 46, 1);
  }
  entry:focus {
      box-shadow: none;
      border: 1px solid rgba(223, 92, 55, 1);
  }

  button, image {
      background: none;
      border: none;
      box-shadow: none;
  }

  button:hover {
      background-color: rgba (255, 255, 255, 0.06);
  }

  /* in case you wanted to give category buttons a different look */
  #category-button {
      margin: 0 10px 0 10px;
  }

  #pinned-box {
      padding-bottom: 5px;
      border-bottom: 1px dotted gray;
  }

  #files-box {
      padding: 5px;
      border: 1px dotted gray;
      border-radius: 15px;
  }
''

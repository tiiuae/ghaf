# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Ghaf lock screen style
{
  writeText,
  ...
}:
writeText "ghaf-lock.css" ''
  window {
      background-color: #121212;
      color: #fff;
  }

  combobox button {
      background: rgba(255, 255, 255, 0.1);
      color: #fff;
  }

  combobox button:focus {
      background: rgba(255, 255, 255, 0.2);
      color: #fff;
  }

  combobox button:hover {
      background: rgba(255, 255, 255, 0.2);
      color: #fff;
  }

  combobox window menu {
      background: rgba(255, 255, 255, 0.1);
      color: #fff;
      border-radius: 7px;
  }

  button {
      box-shadow: none;
      border: none;
      background: rgba(255, 255, 255, 0.1);
      color: #fff;
      border-radius: 7px;
  }

  button:focus {
      box-shadow: inset 0px 0px 0px 2px rgba(255, 255, 255, 0.3);
  }

  button:hover {
      box-shadow: inset 0px 0px 0px 2px rgba(255, 255, 255, 0.3);
  }

  entry {
      box-shadow: none;
      border: none;
      background: rgba(255, 255, 255, 0.1);
      color: #fff;
      border-radius: 7px;
  }

  entry:focus {
      box-shadow: inset 0px 0px 0px 2px rgba(255, 255, 255, 0.3);
  }

  entry:hover {
      box-shadow: inset 0px 0px 0px 2px rgba(255, 255, 255, 0.3);
  }

  #input-field {
      box-shadow: none;
      border: none;
      background: rgba(255, 255, 255, 0.1);
      color: #fff;
      border-radius: 7px;
  }

  #input-field:focus {
      box-shadow: inset 0px 0px 0px 2px rgba(255, 255, 255, 0.3);
  }

  #input-field:hover {
      box-shadow: inset 0px 0px 0px 2px rgba(255, 255, 255, 0.3);
  }

  #user-name {
      margin-top: 15px;
      font-weight: bold;
  }

  #error-label {
      color: #fff;
  }

  #warning-label {
      color: #fff;
  }

  window.focused:not(.hidden) #time-box {
      opacity: 0;
  }
''

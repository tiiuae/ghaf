# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: {
  _file = ./accounts.nix;

  # Account management file for ghaf, allows to declaratively manage user accounts.
  # Main use-case is to centrally administer passwords across builds.
  # The admin account defaults to true even without this setting as not all
  # targets use the modules interface yet.

  config = {
    ghaf.users = {
      # Default admin account
      admin = {
        enable = true;
        initialPassword = "ghaf";
        initialHashedPassword = null;
        hashedPassword = null;
      };
      # Example of a managed user account
      # managed = [
      #   {
      #     name = "some-user";
      #     vms = [
      #       "ghaf-host"
      #       "audio-vm"
      #     ];
      #     initialPassword = null;
      #     initialHashedPassword = null;
      #     hashedPassword = "$y$j9T$SiiIgN1tg8NadUt.YfeT01$Td60m8AC4F8DTFlxkurJ.G8i6lCfit5A7GHal8S49S9";
      #   }
      #   {
      #     name = "some-ui-user";
      #     vms = [
      #       "gui-vm"
      #     ];
      #     initialPassword = null;
      #     initialHashedPassword = null;
      #     hashedPassword = "$y$j9T$SiiIgN1tg8NadUt.YfeT01$Td60m8AC4F8DTFlxkurJ.G8i6lCfit5A7GHal8S49S9";
      #     uid = 1002;
      #   }
      # ];
    };
  };
}

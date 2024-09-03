<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Profiles Configuration

A profile is a set of software needed for a particular use case. All profiles configuration files are in [modules/profiles](https://github.com/tiiuae/ghaf/tree/main/modules/profiles).

To add a new profile, do the following:

1. Create your own configuration file using [modules/profiles/mvp-user-trial.nix](https://github.com/tiiuae/ghaf/blob/main/modules/profiles/mvp-user-trial.nix) as a reference.
2. Depending on the location of your reference appvms, services, or programs change the includes to point to them.
3. Create a new enable option to enable the profile, for example, `new-cool-profile`.
4. In the lower section, under the correct area appvms, services, programs, make sure to describe additional definitions you need.


For example, a `safe-and-unsave-browsing.nix` file with a simple setup that includes business-vm and chrome-vm could look like this:

```
  config = lib.mkIf cfg.enable {
    ghaf = {
      reference = {
        appvms = {
          enable = true;
          chromium-vm = true;
          business-vm = true;
        };

        services = {
          enable = true;
        };

        programs = {
        };
      };

      profiles = {
        laptop-x86 = {
          enable = true;
          netvmExtraModules = [../reference/services];
          guivmExtraModules = [../reference/programs];
          inherit (config.ghaf.reference.appvms) enabled-app-vms;
        };
      };
    };
  };
```
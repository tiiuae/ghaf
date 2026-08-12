# Ghaf Builder Functions

This directory contains reusable builder functions that can be used by both Ghaf internally and downstream projects to create consistent configurations and installers.

## Available Builders

### mkGhafConfiguration

Creates a Ghaf configuration for any supported target type (laptop-x86, orin).

**Parameters (named):**
- `name`: String - Name of the machine (e.g., "lenovo-x1-carbon-gen11")
- `system`: String - Target architecture ("x86_64-linux" or "aarch64-linux")
- `profile`: String - Target profile ("laptop-x86" or "orin")
- `hardwareModule`: Module - NixOS module for hardware-specific configuration
- `variant`: String - Build variant, "debug" (default) or "release"
- `extraModules`: List - Additional NixOS modules (default: [])
- `extraConfig`: Attrs - Additional ghaf.* configuration (default: {})
- `vmConfig`: Attrs - VMM selection, VM resource allocation, and modules (default: {})

**Returns:**
- `name`: Full configuration name (e.g., "lenovo-x1-carbon-gen11-debug")
- `variant`: The build variant
- `hostConfiguration`: The NixOS configuration
- `package`: The built system image
- `extendHost`: Function to extend host with additional modules
- `extendVm`: Function to extend a specific VM with additional modules
- `getVmConfig`: Function to get a VM's final configuration. Takes the `microvm.vms` key, i.e. the
  hyphenated name (`"gui-vm"`, `"net-vm"`), not the `vmConfig.sysvms` key that `extendVm` takes

### mkGhafInstaller

Creates a bootable ISO installer for any Ghaf configuration.

**First-level parameters (named):**
- `self`: Flake self reference
- `lib`: Nixpkgs lib (default: `self.lib`)
- `system`: String - Target architecture (default: `"x86_64-linux"`)
- `extraModules`: List - Additional NixOS modules for the shared installer system (default: `[]`)

**Second-level parameters (named):**
- `name`: String - Base name for the installer (e.g., `"lenovo-x1-carbon-gen11-debug"`)
- `imagePath`: Path - Path to the built Ghaf image package

**Returns:**
- `name`: Full installer name (e.g., "lenovo-x1-carbon-gen11-debug-installer")
- `package`: The built ISO image

## Usage in Downstream Projects

Use the **pre-bound** builders — `ghafConfiguration`, `ghafInstaller`,
`ghafNetbootInstaller`. They are the same builders already bound to ghaf's own `self`, `inputs`
and `lib`, so a downstream never has to construct that bundle by hand.

Getting the bundle right by hand is genuinely hard: `inputs` inside a flake-parts module contains
`self` (the `outputs` function receives it), but the `inputs` **output attribute** of a built flake
does not. So `inputs.ghaf.inputs` is missing exactly the key every ghaf module reads as
`inputs.self`, and the failure surfaces deep inside module evaluation as `attribute 'self' missing`.

### Basic Usage

```nix
{
  inputs = {
    ghaf.url = "github:tiiuae/ghaf";
    nixpkgs.follows = "ghaf/nixpkgs";
  };

  outputs = { self, ghaf, ... }:
  let
    system = "x86_64-linux";

    # Create laptop configuration
    myLaptop = ghaf.builders.ghafConfiguration {
      name = "my-laptop";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = ./hardware-configuration.nix;
      variant = "debug";
      extraModules = [
        ghaf.nixosModules.reference-profiles
        ghaf.nixosModules.profiles
      ];
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
      vmConfig = {
        sysvms.guivm = {
          mem = 8192;
          vcpu = 4;
        };
      };
      # Reach your OWN flake from inside your modules, as `inputs.mine`.
      # `self` and `inputs` in a module are ghaf's; this is how you add a name
      # that resolves on the host AND inside every VM.
      extraInputs = { mine = self; };
    };

    # Create installer. The first argument set configures the shared installer
    # system; the second names the image it installs.
    myInstaller = ghaf.builders.ghafInstaller { inherit system; } {
      name = myLaptop.name;
      imagePath = myLaptop.package;
    };

  in {
    nixosConfigurations.${myLaptop.name} = myLaptop.hostConfiguration;
    packages.${system}.${myLaptop.name} = myLaptop.package;
    packages.${system}.${myInstaller.name} = myInstaller.package;
  };
}
```

### Using vmConfig for VMM and Resource Configuration

The `vmConfig` parameter selects a default system-VM VMM and supports
per-VM VMM and resource overrides. The default VMM is QEMU, while
AdminVM defaults to crosvm on every target. crosvm VMs run as Ghaf's
unprivileged `microvm` user with crosvm's internal minijail disabled, because
its namespace setup requires `CAP_SYS_ADMIN`.

```nix
vmConfig = {
  defaultSysVmVmm = "qemu";

  # System VMs, keyed by the unhyphenated name (guivm, netvm, audiovm,
  # adminvm, idsvm)
  sysvms = {
    guivm = {
      mem = 16384;        # Memory in MB
      vcpu = 8;           # Virtual CPUs
      extraModules = [ ./custom-gui.nix ];
    };
    netvm = {
      mem = 1024;
    };
    audiovm = {
      mem = 512;
    };
    adminvm.vmm = "qemu"; # Optional AdminVM fallback
  };

  # App VMs
  appvms = {
    chromium = {
      mem = 8192;
      vcpu = 4;
      balloonRatio = 2;
      extraModules = [ ./chromium-tweaks.nix ];
    };
  };
};
```

### Extending Configurations

The builder returns composition helpers for extending configurations:

```nix
let
  baseConfig = mkGhafConfiguration {
    name = "my-laptop";
    # ... base configuration
  };

  # Extend host with additional modules
  extendedHost = baseConfig.extendHost [
    { services.someService.enable = true; }
  ];

  # Extend a specific VM
  extendedVm = baseConfig.extendVm "guivm" [
    { services.guiService.enable = true; }
  ];
in
  extendedHost  # or extendedVm
```

## Internal Ghaf Usage

Within Ghaf itself, builders are called from flake-modules:

```nix
# targets/laptop/flake-module.nix
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "x86_64-linux";

  ghaf-configuration = self.builders.mkGhafConfiguration {
    inherit self inputs;
    inherit (self) lib;
  };

  ghaf-installer = self.builders.mkGhafInstaller {
    inherit self system;
    inherit (self) lib;
    extraModules = installerModules;
  };

  target-configs = [
    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen11";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })
  ];

  target-installers = map (t: ghaf-installer {
    name = t.name;
    imagePath = self.packages.${system}.${t.name};
  }) target-configs;

in {
  flake.nixosConfigurations = builtins.listToAttrs (
    map (t: lib.nameValuePair t.name t.hostConfiguration) target-configs
  );
  flake.packages.${system} = builtins.listToAttrs (
    map (t: lib.nameValuePair t.name t.package) (target-configs ++ target-installers)
  );
}
```

## Migration from Legacy Builders

If migrating from `mkLaptopConfiguration` or `mkOrinConfiguration`:

### Old Pattern
```nix
(laptop-configuration "lenovo-x1-carbon-gen11" "debug" (withCommonModules [
  self.nixosModules.hardware-lenovo-x1-carbon-gen11
  {
    ghaf = {
      reference.profiles.mvp-user-trial.enable = true;
      partitioning.disko.enable = true;
    };
  }
]))
```

### New Pattern
```nix
(ghaf-configuration {
  name = "lenovo-x1-carbon-gen11";
  inherit system;
  profile = "laptop-x86";
  hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
  variant = "debug";
  extraModules = commonModules;
  extraConfig = {
    reference.profiles.mvp-user-trial.enable = true;
    partitioning.disko.enable = true;
  };
})
```

Key differences:
- Named parameters instead of positional
- `hardwareModule` separated from `extraModules`
- `extraConfig` sets `ghaf.*` attributes directly
- `vmConfig` for VMM selection and resource allocation (replaces
  `hardware.definition.<vm>.mem/vcpu`)

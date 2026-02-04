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
- `vmConfig`: Attrs - VM resource allocation and modules (default: {})

**Returns:**
- `name`: Full configuration name (e.g., "lenovo-x1-carbon-gen11-debug")
- `variant`: The build variant
- `hostConfiguration`: The NixOS configuration
- `package`: The built system image
- `extendHost`: Function to extend host with additional modules
- `extendVm`: Function to extend a specific VM with additional modules
- `getVmConfig`: Function to get a VM's final configuration

### mkGhafInstaller

Creates a bootable ISO installer for any Ghaf configuration.

**Parameters (named):**
- `name`: String - Base name for the installer (e.g., "lenovo-x1-carbon-gen11-debug")
- `imagePath`: Path - Path to the built Ghaf image package
- `extraModules`: List - Additional NixOS modules for the installer (default: [])

**Returns:**
- `name`: Full installer name (e.g., "lenovo-x1-carbon-gen11-debug-installer")
- `hostConfiguration`: The NixOS configuration for the installer
- `package`: The built ISO image

## Usage in Downstream Projects

### Basic Usage

```nix
{
  inputs = {
    ghaf.url = "github:tiiuae/ghaf";
    nixpkgs.follows = "ghaf/nixpkgs";
  };

  outputs = { self, ghaf, nixpkgs, ... }:
  let
    system = "x86_64-linux";

    # Initialize builders from ghaf
    mkGhafConfiguration = ghaf.builders.mkGhafConfiguration {
      inherit (ghaf) self inputs lib;
    };

    mkGhafInstaller = ghaf.builders.mkGhafInstaller {
      inherit (ghaf) self lib;
      inherit system;
    };

    # Create laptop configuration
    myLaptop = mkGhafConfiguration {
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
        guivm = {
          mem = 8192;
          vcpu = 4;
        };
      };
    };

    # Create installer
    myInstaller = mkGhafInstaller {
      name = myLaptop.name;
      imagePath = self.packages.${system}.${myLaptop.name};
      extraModules = [
        {
          networking.wireless.networks."MyWiFi".psk = "password";
        }
      ];
    };

  in {
    nixosConfigurations.${myLaptop.name} = myLaptop.hostConfiguration;
    packages.${system}.${myLaptop.name} = myLaptop.package;
    packages.${system}.${myInstaller.name} = myInstaller.package;
  };
}
```

### Using vmConfig for Resource Allocation

The `vmConfig` parameter allows you to customize VM resource allocation per-target:

```nix
vmConfig = {
  # System VMs
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

  # App VMs (use ramMb/cores for consistency with appvm definitions)
  appvms = {
    chromium = {
      ramMb = 8192;
      cores = 4;
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
    extraModules = installerModules;
  }) target-configs;

in {
  flake.nixosConfigurations = builtins.listToAttrs (
    map (t: lib.nameValuePair t.name t.hostConfiguration) (target-configs ++ target-installers)
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
- `vmConfig` for resource allocation (replaces `hardware.definition.<vm>.mem/vcpu`)

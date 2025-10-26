# Ghaf Builder Functions

This directory contains reusable builder functions that can be used by both Ghaf internally and downstream projects to create consistent laptop configurations and installers.

## Available Builders

### mkLaptopConfiguration

Creates a laptop configuration with Ghaf modules and profiles.

**Parameters:**
- `machineType`: String - Name/type of the machine (e.g., "my-laptop")
- `variant`: String - Build variant, either "debug" or "release"
- `extraModules`: List - Additional NixOS modules to include

**Returns:**
- `hostConfiguration`: The NixOS configuration
- `variant`: The build variant
- `name`: Generated name in format `"${machineType}-${variant}"`
- `package`: The built system image

### mkLaptopInstaller

Creates a laptop installer ISO image.

**Parameters:**
- `name`: String - Name for the installer (e.g., "my-laptop-installer")
- `imagePath`: String - Path to the image that will be installed
- `extraModules`: List - Additional NixOS modules to include

**Returns:**
- `hostConfiguration`: The NixOS configuration for the installer
- `name`: Generated name in format `"${name}-installer"`
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
    # Get the builder functions from ghaf
    builders = ghaf.builders;

    # Create laptop configuration
    laptop-config = builders.mkLaptopConfiguration {
      inherit (ghaf) self inputs;
      lib = ghaf.lib;
    } "my-laptop" "debug" [
      # Your additional modules here
      ./hardware-configuration.nix
      {
        # Your custom configuration
        ghaf.profiles.graphics.enable = true;
      }
    ];

    # Create installer
    laptop-installer = builders.mkLaptopInstaller {
      inherit (ghaf) self;
      lib = ghaf.lib;
    } "my-laptop" laptop-config.package [
      # Installer-specific modules
      {
        networking.wireless.networks."MyWiFi".psk = "password";
      }
    ];

  in {
    nixosConfigurations.${laptop-config.name} = laptop-config.hostConfiguration;
    packages.x86_64-linux.${laptop-config.name} = laptop-config.package;
    packages.x86_64-linux.${laptop-installer.name} = laptop-installer.package;
  };
}
```

### Advanced Usage with Custom System

```nix
{
  inputs = {
    ghaf.url = "github:tiiuae/ghaf";
    nixpkgs.follows = "ghaf/nixpkgs";
  };

  outputs = { self, ghaf, nixpkgs, ... }:
  let
    system = "x86_64-linux";

    # Import builders with custom system
    mkLaptopConfiguration = import "${ghaf}/lib/builders/mkLaptopConfiguration.nix" {
      self = ghaf;
      inputs = { inherit ghaf nixpkgs; };
      lib = ghaf.lib;
      inherit system;
    };

    mkLaptopInstaller = import "${ghaf}/lib/builders/mkLaptopInstaller.nix" {
      self = ghaf;
      lib = ghaf.lib;
      inherit system;
    };

  in {
    # Use the builders directly
    packages.x86_64-linux.my-laptop-debug =
      (mkLaptopConfiguration "my-laptop" "debug" [
        ./my-hardware.nix
      ]).package;
  };
}
```

## Internal Ghaf Usage

Within Ghaf itself, builders are called directly from flake-modules:

```nix
# targets/laptop/flake-module.nix
{
  lib,
  self,
  inputs,
  ...
}:
let
  # Direct builder function assignment
  laptop-configuration = self.builders.mkLaptopConfiguration;
  laptop-installer = self.builders.mkLaptopInstaller;

  # Then call with parameters
  target-configs = [
    (laptop-configuration "lenovo-x1-carbon-gen11" "debug" [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      { ghaf.reference.profiles.mvp-user-trial.enable = true; }
    ])
  ];
in {
  # Export configurations...
}
```

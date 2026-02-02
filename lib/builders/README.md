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
- `vmConfigurations`: Pre-built VM configurations (for downstream composition)
- `sharedSystemConfig`: The shared system configuration module
- `extendHost`: Function to extend the host configuration
- `extendVm`: Function to extend individual VMs
- `mkCustomAppVm`: Function to create custom app VMs

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

### vmBuilders

Standalone VM builders for downstream composition. Each builder returns a NixOS configuration
that can be extended using `extendModules`.

Available builders:
- `mkAudioVm`: Audio VM with pipewire, speakers, microphone
- `mkNetVm`: Network VM with firewall, networking services
- `mkGuiVm`: GUI VM with desktop environment, display
- `mkAdminVm`: Admin VM with logging, management services
- `mkIdsVm`: IDS VM with intrusion detection
- `mkAppVm`: Application VM builder

### mkSharedSystemConfig

Creates a shared system configuration module that's used across host and all VMs.
This ensures consistent settings (debug/release, timezone, logging, etc.) across all components.

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

### Extending VMs (Downstream Composition)

The new architecture allows downstream projects to extend individual VMs:

```nix
{
  inputs = {
    ghaf.url = "github:tiiuae/ghaf";
    nixpkgs.follows = "ghaf/nixpkgs";
  };

  outputs = { self, ghaf, nixpkgs, ... }:
  let
    builders = ghaf.builders;

    # Create base laptop configuration
    base-laptop = builders.mkLaptopConfiguration {
      inherit (ghaf) self inputs;
      lib = ghaf.lib;
    } "my-laptop" "debug" [];

    # Extend the GUI VM with custom applications
    customGuiVm = base-laptop.extendVm "gui-vm" [
      {
        # Add custom packages to GUI VM
        environment.systemPackages = [ pkgs.vscode ];
      }
    ];

    # Create a custom app VM
    myAppVm = base-laptop.mkCustomAppVm {
      name = "my-custom-app";
      modules = [
        {
          # Custom app configuration
          environment.systemPackages = [ pkgs.firefox ];
        }
      ];
    };

  in {
    # Export configurations...
  };
}
```

### Creating Custom VMs with vmBuilders

For complete control, use the standalone VM builders directly:

```nix
{
  inputs = {
    ghaf.url = "github:tiiuae/ghaf";
    nixpkgs.follows = "ghaf/nixpkgs";
  };

  outputs = { self, ghaf, nixpkgs, ... }:
  let
    builders = ghaf.builders;
    system = "x86_64-linux";

    # Create shared system config for your project
    sharedConfig = builders.mkSharedSystemConfig {
      lib = ghaf.lib;
      variant = "debug";
      sshDaemonEnable = true;
      loggingEnable = true;
    };

    # Create a standalone audio VM
    myAudioVm = builders.vmBuilders.mkAudioVm {
      inherit (ghaf) self inputs;
      inherit system;
      hostParams = {
        hostName = "my-custom-host";
        # ... other host params
      };
      systemConfigModule = sharedConfig;
    };

    # Extend it with custom modules
    extendedAudioVm = myAudioVm.extendModules {
      modules = [
        {
          # Custom audio configuration
          services.pipewire.wireplumber.extraConfig = {
            # ...
          };
        }
      ];
    };

  in {
    # Export as standalone VM for testing
    packages.${system}.my-audio-vm = extendedAudioVm.config.system.build.vm;
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

## 5-Layer Architecture

The VM system is organized in layers for clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 5: Target Compositions (targets/laptop/...)          │
│  - Final NixOS configurations with extendModules exposed    │
│  - Hardware profiles, target-specific settings              │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: Host Modules (modules/, profiles/)                │
│  - Host-specific hardware, profiles                         │
│  - VM instantiation via microvm.vms.<name>.evaluatedConfig  │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: Shared System Config (sharedSystemConfig.nix)     │
│  - debug/release profiles, timezone, logging                │
│  - Passed to ALL VMs and host via specialArgs               │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: VM Role Modules (vmConfigurations/mkXxxVm.nix)    │
│  - Role-specific configuration (audio, net, gui, etc.)      │
│  - Returns nixosSystem with extendModules                   │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Base VM Config (vmConfigurations/base.nix)        │
│  - Common VM settings (stateVersion, hypervisor, etc.)      │
│  - GIVC integration, preservation, identity                 │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│  Layer 0: Pure Library Functions (lib/vm.nix)               │
│  - Helper functions with no implicit config access          │
│  - mkVmSystemParams, mkStoreShares, extendVmConfig, etc.    │
└─────────────────────────────────────────────────────────────┘
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

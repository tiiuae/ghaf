<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Installer

## Configuring and Building Installer for Ghaf

You can obtain the installation image for your Ghaf configuration. To check possible configuration options, see [Modules Options](../ref_impl/modules_options.md#ghafinstallerenable).

1. Set `ghaf.installer.enable` to `true`.
2. Add nixos-generators module to `ghaf.installer.imgModules` list to configure installer image type.
3. Choose installer modules from `ghaf.installer.installerModules` and set `ghaf.installer.enabledModules` to list of their names.
4. Write code for the installer in `ghaf.installer.installerCode`.

```nix
{config, ...}: {
  ghaf.installer = {
    enable = true;
    imgModules = [
      nixos-generators.nixosModules.raw-efi
    ];
    enabledModules = ["flushImage"];
    installerCode = ''
      echo "Starting flushing..."
      if sudo dd if=${config.system.build.${config.formatAttr}} of=/dev/${config.ghaf.installer.installerModules.flushImage.providedVariables.deviceName} conv=sync bs=4K status=progress; then
          sync
          echo "Flushing finished successfully!"
          echo "Now you can detach installation device and reboot to Ghaf."
      else
          echo "Some error occured during flushing process, exit code: $?."
          exit
      fi
    '';
  };
}
```

After that you can build an installer image using this command:

```sh
nix build .#nixosConfigurations.<CONFIGURATION>.config.system.build.installer
```

## Adding Installer Modules

To add an installer module, replace the corresponding placeholders with your code and add this to your configuraiton:

```nix
ghaf.installer.installerModules.<MODULE_NAME> = {
  requestCode = ''
    # Your request code written in Bash
  '';
  providedVariables = {
    # Notice the dollar sign before the actual variable name in Bash.
    <VARIABLE_NAME> = "$<VARIABLE_NAME>";
  };
};
```

## Built-in Installer Modules

Provided variables show variable names in Nix. For actual names of variables in Bash, see the sources of the module.

### flushImage

Provided variables:

- deviceName: name of the device on which image should be flushed (e.g. "sda", "nvme0n1")


{...}: {
  ghaf.installer.installerModules.flushImage = {
    requestCode = ''
      lsblk
      read -p "Device name [e.g. sda]: " DEVICE_NAME
    '';
    providedVariables = {
      deviceName = "$DEVICE_NAME";
    };
  };
}

{
  config,
  options,
  lib,
  ...
}:
with lib; let
  cfg = config.ghaf.hardware.passthrough;
  passthroughOptions = {
    vid = mkOption {
      description = mdDoc "Virtual id.";
      type = types.str;
      default = "";
      example = "8086";
    };
    pid = mkOption {
      description = mdDoc "PCI id.";
      type = types.str;
      default = "";
      example = "51f1";
    };
  };
  passthroughOptions' =
    {
      addr = mkOption {
        description = mdDoc "PCI device address.";
        type = types.str;
        default = "";
        example = "0000:00:14.3";
      };
    }
    // passthroughOptions;
in {
  options.ghaf.hardware.passthrough = {
    network = passthroughOptions';
    gpu = passthroughOptions';
    usb = passthroughOptions;
  };

  config = let
    allSet = name: builtins.all (map (a: a != "") (builtins.attrValues cfg.${name}));
  in
    mkMerge [
      {
        assertions = map (name: {
          assertion = !allSet name;
          message = "All values in ${name} passthrough must be defined!";
        }) (builtins.attrNames options.ghaf.hardware.passthrough);
      }
      (mkIf (allSet "usb") {
        services.udev.extraRules = ''
          # Add usb to kvm group
          SUBSYSTEM=="usb", ATTR{idVendor}=="${cfg.usb.vid}", ATTR{idProduct}=="${cfg.usb.pid}", GROUP+="kvm"
        '';
        ghaf.virtualization.microvm.guivm.extraModules = [
          {
            microvm.qemu.extraArgs = [
              "-usb"
              "-device"
              "usb-host,vendorid=0x${usbInputVid},productid=0x${usbInputPid}"
            ];
          }
        ];
      })
      (mkIf (cfg.network.addr != "") {
        ghaf.virtualization.microvm.netvm.extraModules = [
          {
            microvm.devices = lib.mkForce [
              {
                bus = "pci";
                path = cfg.network.addr;
              }
            ];
          }
        ];
      })
      (mkIf (cfg.gpu.addr != "") {
        ghaf.virtualization.microvm.guivm.extraModules = [
          {
            microvm.devices = lib.mkForce [
              {
                bus = "pci";
                path = cfg.gpu.addr;
              }
            ];
          }
        ];
      })
      (
        mkIf (builtins.any (map allSet ["network" "gpu"])) (let
          networkPair = optional (allSet "network") (cfg.network.vid + ":" + cfg.network.pid);
          gpuPair = optional (allSet "gpu") (cfg.gpu.vid + ":" + cfg.gpu.pid);
          idsPairs = concatStringsSep "," (networkPair ++ gpuPair);
        in {
          boot.kernelParams = [
            "vfio-pci.ids=${idPairs}"
          ];
        })
      )
    ];
}

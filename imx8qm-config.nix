{
  pkgs = import <nixpkgs> {
    overlays = [
      (import ./overlays/common.nix)
      (import ./overlays/imx8qm.nix)
      (final: prev:
        {
          makeModulesClosure = args: prev.makeModulesClosure (args // {
            rootModules = [ "dm-verity" "loop" ];
          });
        })
    ];
  };
}


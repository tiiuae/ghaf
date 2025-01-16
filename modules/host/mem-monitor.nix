{ pkgs, config, ... }:
{
  config = {
    environment.systemPackages = [ pkgs.mem-monitor ];
    systemd.services =
      builtins.foldl'
        (
          result: name:
          result
          // (
            let
              microvmConfig = config.microvm.vms.${name}.config.config.microvm;
            in
            {
              "ghaf-mem-monitor-${name}" = {
                description = "Monitor MicroVM '${name}' memory levels";
                after = [ "microvm@${name}.service" ];
                requires = [ "microvm@${name}.service" ];
                serviceConfig = {
                  Type = "simple";
                  WorkingDirectory = "${config.microvm.stateDir}/${name}";
                  ExecStart = "${pkgs.mem-monitor}/bin/ghaf-mem-monitor -s ${name}.sock -m ${
                    builtins.toString (microvmConfig.mem * 1024 * 1024)
                  } -M ${builtins.toString ((microvmConfig.mem + microvmConfig.balloonMem) * 1024 * 1024)}";
                };
              };
            }
          )
        )
        {
          balloon-monitor =
            let
              balloonvms = builtins.map (name: "ghaf-mem-monitor-" + name + ".service") (
                builtins.filter (name: (config.microvm.vms.${name}.config.config.microvm.balloonMem or 0) >= 0) (
                  builtins.attrNames config.microvm.vms
                )
              );
            in
            {
              description = "Monitor MicroVM balloons";
              after = balloonvms;
              requires = balloonvms;
              wantedBy = [ "microvms.target" ];
              script = ":";
            };
        }
        (
          builtins.filter (name: (config.microvm.vms.${name}.config.config.microvm.balloonMem or 0) >= 0) (
            builtins.attrNames config.microvm.vms
          )
        );
  };
}

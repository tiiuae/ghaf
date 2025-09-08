{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.appvm;
  vms = lib.filterAttrs (_: vm: vm.enable) cfg.vms;
  vmsWithVtpm = lib.filterAttrs (_name: vm: vm.vtpm.enable) vms;

  swtpm-proxy-shim = inputs.swtpm-proxy-shim.packages.${pkgs.stdenv.hostPlatform.system};

  mkSwtpmProxyService = name: cport: {
    description = "swtpm proxy for ${name}";
    script = ''
      ${swtpm-proxy-shim}/bin/swtpm-proxy --type vsock \
        --control-port ${toString cport} \
        --control-retry-count 30 \
        /var/lib/microvms/${name}-vm/vtpm.sock \
        ${toString config.ghaf.networking.hosts.admin-vm.cid} # admin-vm is hardcoded to host the vtpm daemons
    '';
    serviceConfig = {
      Type = "exec";
      Restart = "always";
      User = "microvm";
    };
    wantedBy = [ "microvms.target" ];
    before = [ "microvm@${name}-vm.service" ];
    after = [ "microvm@admin-vm.service" ];
    wants = [ "microvm@admin-vm.service" ];
  };
in
lib.mkIf cfg.enable {
  # Spawn a swtpm-proxy on the host for each VM with vtpm enabled
  systemd.services = lib.mapAttrs' (
    name: vm:
    lib.attrsets.nameValuePair "swtpm-proxy-${name}" (mkSwtpmProxyService name vm.vtpm.basePort)
  ) vmsWithVtpm;
}

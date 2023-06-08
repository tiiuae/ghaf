{ config, pkgs, modulesPath, lib, ...}:
let
   #User configuration
   #To enable docker, make sure all required kernel configs are enabled
   enable-docker = false;
   blacklisted-kernel-modules = [];
   system-packages = [];

   #Private
   docker-system-packages =  if enable-docker then [ pkgs.nftables ] else [];
   blacklist-iptables = if enable-docker then ["ip_tables"] else [];
   blacklisted-modules = blacklisted-kernel-modules ++ blacklist-iptables;
   all-system-packages = system-packages ++ docker-system-packages;
in
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/installer/sd-card/sd-image.nix")
    ../../development/authentication.nix
    ../../development/ssh.nix
  ];

  nixpkgs = {
       localSystem.config = "x86_64-unknown-linux-gnu";
       crossSystem.config = "riscv64-unknown-linux-gnu";
  };


  /* system version */
  /* ============== */

  #system.stateVersion = "23.05";
  system.stateVersion = "22.11";


  /* Boot configuration */
  /* ================== */
  
  boot.blacklistedKernelModules = blacklisted-modules;
  boot.kernelParams = [ "root=/dev/mmcblk0p2" "rootdelay=5"  ];
  boot.consoleLogLevel = 4;
  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  /* General */
  /* ======= */

  disabledModules = [ "profiles/all-hardware.nix" ];
  #required for alfred
  environment.noXlibs = false;
  environment.systemPackages = all-system-packages;


  /* Networking */
  /* ========== */

  networking.hostName = "ghaf-host";
  networking.useDHCP = true;

  networking.firewall = {
   /* 
    * Firewall disabled for error, "You can not use nftables and iptables at the same time. 
    *  networking.firewall.enable must be set to false."
    *
    * https://github.com/NixOS/nixpkgs/issues/161428
    */
    enable = false; #!enable-docker;
    allowedTCPPorts = [ 22 80 443 ];
    allowedUDPPortRanges = [
      { from = 4000; to = 4007; }
      { from = 8000; to = 8010; }
    ];
  };


  /* Services */
  /* ======== */
 
  #avahi daemon
  services.avahi = {
    enable = true;
    nssmdns = true;
    publish.addresses = true;
    publish.domain = true;
    publish.enable = true;
    publish.userServices = true;
    publish.workstation = true;
  };
  services.openssh.enable = true;


  /* Virtualization */
  /* ============== */
   
  virtualisation.docker = {
    enable = enable-docker;
    enableOnBoot = enable-docker;
    extraOptions = "--iptables=false --ip6tables=false";
  };

  networking.nftables.enable = if enable-docker then true else false;
  networking.networkmanager.firewallBackend = if enable-docker then "nftables" else "iptables"; #Doesn't work as of now

  users.extraGroups.docker.members = [ "ghaf" ];
}

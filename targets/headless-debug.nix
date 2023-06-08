{pkgs, ... } :
{
  environment.systemPackages = with pkgs; [
    #bmon
    #clang
    #cmake
    #gcc11
    #git
    #glibc.static
    #gnumake
    #go
    #lsb-release
    #udev
    #vim
    #avahi-compat
    #go
    #hostapd
    #iperf3
    #irqbalance
    #nettools
    #nssmdns
    #openssl
  ];
}

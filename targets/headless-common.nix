{pkgs, ... } :
{
  environment.systemPackages = with pkgs; [
    #avahi-compat        #avahi compat library
    #hostapd             #host access point daemon
    #iperf3              #network testing
    #irqbalance          #irq balancer
    #nettools            #network tools
    #nssmdns             #name service switch and multicast dns
    #openssl             #open ssl

    # Add/Enable other packages here
    #postgresql          #postgres
    #sqlite              #sql lite
    #iw                  #wireless
    #nats-server         #NATS server
    #batctl              #Batman Mesh control
    #alfred              #Batman mesh alfred
    #wireless-regdb      #wireles regulatory database
    #wpa_supplicant      #wpa supplicant
    #docker              #docker support
    ];
}

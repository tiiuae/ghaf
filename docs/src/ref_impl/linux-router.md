<!--
	Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
	SPDX-License-Identifier: CC-BY-SA-4.0
-->

# How to Use a Linux Laptop or Computer as a Router for Ghaf.

Because Ghaf’s Wifi is reserved by NetVM an additional network is needed for a debugging
setup. A Linux computer can be used to provide internet accces to Ghaf. The Linux computer,
for instance a laptop with a mainstream Linux distro can act as a router.

The role of the Linux computer is to forward its access to internet via a shared Ethernet
connection to Ghaf on Jetson.

---

## Preparations

1. Make sure the Linux computer is *fully connected* to the internet and that an Ethernet
   device *is free* to be configured for sharing. Typically the computer would have internet 
   over its Wifi device leaving the Ethernet device unused. These instructions do not 
   describe how to provide internet access to the router/laptop using Wifi.

1. Connect the Linux computer using an Ethernet cable to Jetson in a peer-to-peer fashion.

1. The Ethernet device in Jetson is called eth0 but in Linux it probably has another name.
	Note that most Linux distributions use NetworkManager (providing for instance the nmcli
	tool) and Ghaf uses networkd (providing networkctl).

	You can inspect the devices and IP adresses in a NetworkManager system using `nmcli c s`
	and `ifconfig`. In a networkd system like Ghaf you can use `ip address show eth0` and `ifconfig`
	( the `ip` command is usually also available on NetworkManager systems)

##  On the Linux computer

1.	Find out the name of the Ethernet device using nmcli. Typically
	its called *'Wired Connection 1'* or something similar. Its type will be declared as Ethernet.

	Take note of the connection name and the  Ethernet device name.

    ```
	connection show

    ```

1. Clone the Ethernet device with:

    ```
	sudo nmcli connection clone Wired\ Connection\ 1 Shared\ Connection

1.	Set ipv4 mode to shared and disable ipv6

    ```
	sudo nmcli connection modify Shared\ Connection ipv4.method shared
	sudo nmcli connection modify Shared\ Connection ipv6.method disabled
    ```

1.	Make sure the new configuration is active

    ```
	sudo nmcli connection down Wired\ Connection\ 1
	sudo nmcli connection down Shared\ Connection
	sudo nmcli connection reload Shared\ Connection
	sudo nmcli connection up Shared\ Connection
    ```

1.	Note the IP address and Ethernet device name of Shared Connection using.

    ```
    nmcli connection show
	if config <ethernet device name
    ```

	The IP could be something like '10.42.0.1'. Note the namespace or the netmask.

## On Ghaf

1.	Log in to Ghaf using the serial console and for instance picocom

    ```
	sudo picocom -b 115200 /dev/ttyACM0
    ```

1.	Set the IP address of Ethernet on Ghaf within the namespace of the Shared Connection.
	Do not use exactly the same IP address as the router.

    ```
	sudo ip address add 10.42.0.2/24 dev eth0
	sudo ifconfig eth0 down
	sudo ifconfig eth0 up
    ```

1. You can verify the result from Ghaf with

    ```
	ip address show eth0
	ifconfig
	ping 10.42.0.1
	host elisa.fi
	ping -c2 elisa.fi
    ```

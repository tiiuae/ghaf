<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# i.MX 8QM Ethernet Passthrough

The i.MX 8QuadMax (i.MX 8QM, iMX8QM, imx8qm) passthrough host setup relies as much as possible on the default i.MX 8QM MEK (imx8qm-mek) device tree configuration. Some guidance on what is required for passthrough to work on i.MX 8 can be found in the XEN device trees.

This document provides a detailed description of what has been done and why. For the more impatient readers, the example device tree files for i.MX 8QM guest and host with Ethernet passthrough are available here:
 - Full host device tree: [imx8qm-mek_conn-host.dts](imx8qm-mek_conn-host.dts)
 - Full guest device tree: [imx8qm-mek_conn-guest.dts](imx8qm-mek_conn-guest.dts)

**NOTE 20.12.2022:**
At the current state, the passthrough is not completely functional. The Ethernet device (fec1) or even both devices (fec1 and fec2) can be set up in the guest. The devices respond and seem functional, the device node does activate, the drivers load correctly, the power state of the device changes to active, and the link state of the Ethernet connection seems to change correctly. However, for some reason, no actual Ethernet data packages go through the Ethernet adapter. The most visible issue is that no interrupts come to the Ethernet devices.

See the following topics:

- [i.MX 8QM Ethernet Passthrough](#imx-8qm-ethernet-passthrough)
  - [Host Kernel Configuration](#host-kernel-configuration)
  - [Host Device Tree Explained](#host-device-tree-explained)
    - [Other Notes About Passthrough](#other-notes-about-passthrough)
  - [Changes in U-Boot](#changes-in-u-boot)
  - [Running Platform Device Passthrough in QEMU](#running-platform-device-passthrough-in-qemu)
  - [Guest Setup](#guest-setup)
    - [Adding Devices to Guest](#adding-devices-to-guest)
    - [Some Final Touches for Guest Devices](#some-final-touches-for-guest-devices)
  - [Compiling the Device Tree Source to Binary Form](#compiling-the-device-tree-source-to-binary-form)
    - [Compiling for Guest](#compiling-for-guest)
    - [Compiling for Host](#compiling-for-host)
  - [Running QEMU with Passthrough Platform Devices](#running-qemu-with-passthrough-platform-devices)

_________________

## Host Kernel Configuration

Kernel version 5.10 was used during the setup. For the passthrough to work, a few kernel configuration options need to be added to the default i.MX 8QM configuration:

- CONFIG_VFIO_PLATFORM=y
- CONFIG_IOMMU_DEFAULT_PASSTHROUGH=y
- CONFIG_VFIO_PLATFORM=y
- CONFIG_ARM_SMMU_V3_SVA=y


## Host Device Tree Explained

The default Freescale i.MX 8QM MEK configuration is included and then updated to get the Ethernet device passthrough configuration added on top of the original device configuration.

There are two problems with using the i.MX 8 XEN configuration as a reference. The first issue is that the configuration between XEN and KVM do not map one to one. The second issue is more specific to Ethernet passthrough, as i.MX 8 XEN configuration does not set up passthrough for Ethernet so most of the configuration needs to be figured out from scratch.


    #include "freescale/imx8qm-mek.dts"
    / {
        domu {
            /*
            * There are 5 MUs, 0A is used by Dom0, 1A is used
            * by ATF, so for DomU, 2A/3A/4A could be used.
            * SC_R_MU_0A
            * SC_R_MU_1A
            * SC_R_MU_2A
            * SC_R_MU_3A
            * SC_R_MU_4A
            * The rsrcs and pads will be configured by uboot scu_rm cmd
            */
            #address-cells = <1>;
            #size-cells = <0>;
            doma {
                compatible = "xen,domu";
                /*
                * The name entry in VM configuration file
                * needs to be same as here.
                */
                domain_name = "DomU";
                /*
                * The reg property will be updated by U-Boot to
                * reflect the partition id.
                */
                reg = <0>;
                
                /*
                * Initialize and activate the Mailbox MU2A at boot
                */
                init_on_rsrcs = <
                    IMX_SC_R_MU_2A
                >;

                /*
                * Mark the Mailbox and Ethernet adapter power domains available to guest
                */
                rsrcs = <
                    IMX_SC_R_MU_2A
                    IMX_SC_R_ENET_0
                >;

                /* 
                * Mark the pads for ethernet adapter fec1 available to guest
                */
                pads = <
                    IMX8QM_ENET0_MDIO
                    IMX8QM_ENET0_MDC
                    IMX8QM_ENET0_REFCLK_125M_25M

                    IMX8QM_ENET0_RGMII_TXC
                    IMX8QM_ENET0_RGMII_TX_CTL
                    IMX8QM_ENET0_RGMII_TXD0
                    IMX8QM_ENET0_RGMII_TXD1
                    IMX8QM_ENET0_RGMII_TXD2
                    IMX8QM_ENET0_RGMII_TXD3
                    IMX8QM_ENET0_RGMII_RXC
                    IMX8QM_ENET0_RGMII_RX_CTL
                    IMX8QM_ENET0_RGMII_RXD0
                    IMX8QM_ENET0_RGMII_RXD1
                    IMX8QM_ENET0_RGMII_RXD2
                    IMX8QM_ENET0_RGMII_RXD3
                    IMX8QM_COMP_CTL_GPIO_1V8_3V3_ENET_ENETB

                    IMX8QM_SCU_GPIO0_07
                    IMX8QM_SPI0_CS1
                    IMX8QM_SPI2_CS1
                    IMX8QM_SAI1_RXFS
                    IMX8QM_SAI1_RXC
                >;

                /* GPIOS as default from imxqm XEN device tree */
                gpios = <&lsio_gpio1 13 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio1 19 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio1 27 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio1 28 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio1 30 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio4 1 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio4 3 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio4 6 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio4 9 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio4 11 GPIO_ACTIVE_HIGH>,
                    <&lsio_gpio4 19 GPIO_ACTIVE_HIGH>,
                    <&lsio_gpio4 22 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio4 25 GPIO_ACTIVE_HIGH>,
                    <&lsio_gpio4 26 GPIO_ACTIVE_HIGH>,
                    <&lsio_gpio4 27 GPIO_ACTIVE_LOW>,
                    <&lsio_gpio4 29 GPIO_ACTIVE_LOW>;
            };
        };
    };

    /*
     * Add iommus property for the passed through device nodes to allow setting up vfio  
     * The device type "compatible" is changed to prevent the system from loading a  
     * driver the the adapter.  
     * Most other properties are removed from the adapter.
     */
    &fec1 {
        iommus = <&smmu 0x12 0x7f80>;
        compatible = "fsl,dummy";
        status = "okay";

        /delete-property/ power-domains;
        /delete-property/ clocks;
        /delete-property/ clock-names;
        /delete-property/ assigned-clocks;
        /delete-property/ assigned-clock-rates;
        /delete-property/ phy-handle;
        /delete-property/ pinctrl-names;
        /delete-property/ pinctrl-0;
    };

    /* 
     * The device is not being used by guest. Just to make sure it is removed from iommu
     * group and disabled.
     */
    &fec2 {
        /delete-property/ iommus;
        status = "disabled";
    };

    /*
     * Timer device for fec1
    &enet0_lpcg {
        iommus = <&smmu 0x12 0x7f80>;
        compatible = "fsl,dummy";
        status = "okay";
        /delete-property/ power-domains;
        /delete-property/ clocks;
        /delete-property/ clock-names;
        /delete-property/ assigned-clocks;
        /delete-property/ assigned-clock-rates;
        /delete-property/ pinctrl-0;
    };

    &enet1_lpcg {
        /delete-property/ iommus;
        status = "disabled";
    };

    &lsio_mu2 {
        iommus = <&smmu 0x12 0x7f80>;
        compatible = "fsl,dummy";
        status = "okay";
    };

    /*
    * Remove iommus properties from other devices which are not passed through for  Network VM
    */
    &usdhc1 {
        /delete-property/ iommus;
    };

    &usdhc2 {
        /delete-property/ iommus;
    };

    &usdhc3 {
        /delete-property/ iommus;
    };

    &sata {
        /delete-property/ iommus;
    };

    &usbotg3 {
        /delete-property/ iommus;
    };

    &usbotg3_cdns3 {
        /delete-property/ iommus;
    };


### Other Notes About Passthrough

- All devices which belong to the same VFIO/IOMMU group need to be passed through to the guest.
- To prevent the device from being initialized by the host, change the device-compatible property to a dummy such as "fsl,dummy".
- The device status need needs to be "okay" for the device node to be available.
- If U-Boot finds devices that appear in the doma _rsrcs_ that contains the properties listed below, the device will get removed from the DTB:
    - power-domains
    - clocks
    - clock-names
    - assigned-clocks
    - assigned-clock-rates
    - pinctrl-0


## Changes in U-Boot

In our host device tree, we defined a couple of "rsrcs" resources to be handed over to the guest system. The ownership of these registers needs to be transferred to the guest after loading our device tree and before the actual boot. This can be done in U-Boot with a command:

    scu_rm dtb ${fdt_addr}

The easiest way to accomplish this automatically during boot is to add the "scu_rm" to the default i.MX 8QM U-Boot "boot_os" command and save the changes as below:

    setenv boot_os 'scu_rm dtb ${fdt_addr}; booti ${loadaddr} - ${fdt_addr};'
    saveenv


## Running Platform Device Passthrough in QEMU

Before you start QEMU, the passedthrough devices need to be bind to the VFIO driver.

In some cases, the default driver needs to be unbind before the device can be bind to VFIO. However, in this case, all devices were changed to use the dummy device type in the device tree, so the step below is not required for this setup.

    echo 5d1d0000.mailbox > /sys/bus/platform/devices/5d1d0000.mailbox/driver/unbind
    echo 5b040000.ethernet > /sys/bus/platform/devices/5b040000.ethernet/driver/unbind
    echo 5b230000.clock-controller > /sys/bus/platform/devices/5b230000.clock-controller/driver/unbind

The VFIO driver allows user-level access to the devices. Binding required devices to VFIO can be done as below:

    echo vfio-platform  > /sys/bus/platform/devices/5d1d0000.mailbox/driver_override
    echo 5d1d0000.mailbox > /sys/bus/platform/drivers/vfio-platform/bind

    echo vfio-platform > /sys/bus/platform/devices/5b040000.ethernet/driver_override
    echo 5b040000.ethernet > /sys/bus/platform/drivers/vfio-platform/bind

    echo vfio-platform > /sys/bus/platform/devices/5b230000.clock-controller/driver_override
    echo 5b230000.clock-controller > /sys/bus/platform/drivers/vfio-platform/bind

After binding the devices to VFIO so it is possible to pass the devices to QEMU using "**-device vfio-platform**" arguments as below. The order in which the device arguments are given to QEMU may have an effect on some device properties such as interrupts.
    
    -device vfio-platform,host=5b230000.clock-controller
    -device vfio-platform,host=5b040000.ethernet
    -device vfio-platform,host=5d1d0000.mailbox


## Guest Setup

Before starting the virtual machine with passed-through devices, we need to define our virtual machine device tree. One way of gaining a template for our QEMU device tree is by starting our QEMU instance and requesting a dump of its device tree in the DTB format as below.

DTB is a binary format of the device tree so we also need to use the command line tool device tree compiler **dtc** to convert the binary device tree to a more human-friendly device tree source format. Converting the device tree to source format may give a few warnings of missing or unrecognized properties and such but that is normal.

    qemu-system-aarch64 \
        -M virt,gic-version=host,dumpdtb=virt.dtb -enable-kvm -nographic
    
    # Convert binary to source device tree format
    dtc -I dtb -O dts virt.dtb > virt.dts

This will provide a "**virt.dts**" file which can be used as a base for adding our passedthrough devices. The U-Boot device tree may change based on the U-Boot version, so the guest device tree may need some maintenance every now and then.


### Adding Devices to Guest

The platform devices which are going to get passed through should be added to the QEMU device tree **platform** bus section.

In this case, the main devices are **fec1**, **enet0_lpcg** and **lsio_mu2**. At the time of writing, the platform bus address in QEMU is "**c000000**" but that can be changed within the following code (needs recompiling QEMU) or it might change during some the QEMU code update.

	platform@c000000 {
		compatible = "qemu,platform\0simple-bus";
		interrupt-parent = <0x8001>;
		#address-cells = <0x02>;
		#size-cells = <0x02>;

        /* Devices register remapping 
		// ranges = <0xc000000 0x00 0xc000000 0x2000000>;
		ranges = <0x00 0x5b230000 0x00 0xc000000 0x00 0x10000>,
				 <0x00 0x5b040000 0x00 0xc010000 0x00 0x10000>,
				 <0x00 0x5d1d0000 0x00 0xc020000 0x00 0x10000>;

        /*
        * Fec1 device configuration
        * Mostly the same that was set in the original host device configuration
        * The original interrupts can be left here as reference but they are updated at the end of config
        */
        fec1: ethernet@5b040000 {
            reg = <0x00 0x5b040000 0x00 0x10000>;
            interrupts = <GIC_SPI 258 IRQ_TYPE_LEVEL_HIGH>,
                <GIC_SPI 256 IRQ_TYPE_LEVEL_HIGH>,
                <GIC_SPI 257 IRQ_TYPE_LEVEL_HIGH>,
                <GIC_SPI 259 IRQ_TYPE_LEVEL_HIGH>;
            clocks = <&enet0_lpcg 4>,
                <&enet0_lpcg 2>,
                <&enet0_lpcg 3>,
                <&enet0_lpcg 0>,
                <&enet0_lpcg 1>;
            clock-names = "ipg", "ahb", "enet_clk_ref", "ptp", "enet_2x_txclk";
            assigned-clocks = <&clk IMX_SC_R_ENET_0 IMX_SC_PM_CLK_PER>,
                    <&clk IMX_SC_R_ENET_0 IMX_SC_C_CLKDIV>;
            assigned-clock-rates = <250000000>, <125000000>;
            fsl,num-tx-queues=<1>;
            fsl,num-rx-queues=<1>;
            power-domains = <&pd IMX_SC_R_ENET_0>;
            status = "okay";
        };

        /*
        * Fec1 devices clock controller device configuration
        * Mostly the same that was set in the original host device configuration
        * The actual clocks are nor configured so those need to be added to guest
        */
        enet0_lpcg: clock-controller@5b230000 {
            compatible = "fsl,imx8qxp-lpcg";
            reg = <0x00 0x5b230000 0x00 0x10000>;
            #clock-cells = <1>;
            clocks = <&clk IMX_SC_R_ENET_0 IMX_SC_PM_CLK_PER>,
                <&clk IMX_SC_R_ENET_0 IMX_SC_PM_CLK_PER>,
                <&conn_axi_clk>,
                <&clk IMX_SC_R_ENET_0 IMX_SC_C_TXCLK>,
                <&conn_ipg_clk>,
                <&conn_ipg_clk>;
            bit-offset = <0 4 8 12 16 20>;
            clock-output-names = "enet0_lpcg_timer_clk",
                        "enet0_lpcg_txc_sampling_clk",
                        "enet0_lpcg_ahb_clk",
                        "enet0_lpcg_rgmii_txc_clk",
                        "enet0_lpcg_ipg_clk",
                        "enet0_lpcg_ipg_s_clk";
            power-domains = <&pd IMX_SC_R_ENET_0>;
            status = "okay";
        };

        /*
        * Mailbox device for Fec1 (and SCU)
        * The host needs its own Mailbox (lsio_mu1 by default) and SCU
        * The original interrupt can be left here as reference but that is updated at the end of config
        */
        lsio_mu2: mailbox@5d1d0000 {
			compatible = "fsl,imx8-mu-scu", "fsl,imx8qm-mu", "fsl,imx6sx-mu";
			reg = <0x00 0x5d1d0000 0x00 0x10000>;
            interrupts = <GIC_SPI 178 IRQ_TYPE_LEVEL_HIGH>;
			#mbox-cells = <0x02>;
			status = "okay";
		};
	};

The actual devices which were passed through may have some dependencies (such as clocks) which also need to be configured in the guest for the main devices to work properly. In most cases, they can be just copy-pasted from the original host configuration with a few minor alterations. Required dependencies need a bit of manual labor and depend on case to case.

The main key is to go through the whole original device tree and list out device node names that are used by the passedthrough devices. This may require several passes as the dependencies may also contain some dependencies of their own. On top of the requirements, it is good also to check if the passedthrough devices are used by some other devices. 

Some devices may be used through a controller, such as **lsio_mu2** is used by the main system control unit **scu**. In this case, the dependencies consist of several clock devices and their controller and also the i.MX 8 system control unit **SCU** device with its internals.

The assisting devices can be added just before the start "**platform@c000000**" bus configuration section: 

    /**
     * Several clocks and a regulator copied from original host config.
     **/
	clk_dummy: clock-dummy {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <0>;
		clock-output-names = "clk_dummy";
	};

	xtal32k: clock-xtal32k {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <32768>;
		clock-output-names = "xtal_32KHz";
	};

	xtal24m: clock-xtal24m {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <24000000>;
		clock-output-names = "xtal_24MHz";
	};

	reg_fec2_supply: fec2_nvcc {
		compatible = "regulator-fixed";
		regulator-name = "fec2_nvcc";
		regulator-min-microvolt = <1800000>;
		regulator-max-microvolt = <1800000>;
    //	gpio = <&max7322 0 GPIO_ACTIVE_HIGH>;
		enable-active-high;
		status = "okay";
	};

	conn_axi_clk: clock-conn-axi {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <333333333>;
		clock-output-names = "conn_axi_clk";
	};

	conn_ahb_clk: clock-conn-ahb {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <166666666>;
		clock-output-names = "conn_ahb_clk";
	};

	conn_ipg_clk: clock-conn-ipg {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <83333333>;
		clock-output-names = "conn_ipg_clk";
	};

	conn_bch_clk: clock-conn-bch {
		compatible = "fixed-clock";
		#clock-cells = <0>;
		clock-frequency = <400000000>;
		clock-output-names = "conn_bch_clk";
	};

    /**
     * imx8 SCU device and its content with changed to use "lsio_mu2" mailbox
     * The original scu used lsio_mu1 so we need to use one of lsio_mu2 to lsio_mu4
     **/
	scu {
		compatible = "fsl,imx-scu";
		mbox-names = "tx0", "rx0", "gip3";
		mboxes = <&lsio_mu2 0 0
			&lsio_mu2 1 0
			&lsio_mu2 3 3>;

		pd: imx8qx-pd {
			compatible = "fsl,imx8qm-scu-pd", "fsl,scu-pd";
			#power-domain-cells = <1>;
			status = "okay";

			wakeup-irq = <235 236 237 258 262 267 271
					345 346 347 348>;
		};

		clk: clock-controller {
			compatible = "fsl,imx8qm-clk", "fsl,scu-clk";
			#clock-cells = <2>;
			clocks = <&xtal32k &xtal24m>;
			clock-names = "xtal_32KHz", "xtal_24Mhz";
		};

		iomuxc: pinctrl {
			compatible = "fsl,imx8qm-iomuxc";
		};

		ocotp: imx8qm-ocotp {
			compatible = "fsl,imx8qm-scu-ocotp";
			#address-cells = <1>;
			#size-cells = <1>;
			read-only;

			fec_mac0: mac@1c4 {
				reg = <0x1c4 6>;
			};

			fec_mac1: mac@1c6 {
				reg = <0x1c6 6>;
			};
		};

		rtc: rtc {
			compatible = "fsl,imx8qm-sc-rtc";
		};

		watchdog {
			compatible = "fsl,imx8qm-sc-wdt", "fsl,imx-sc-wdt";
			timeout-sec = <60>;
		};

		tsens: thermal-sensor {
			compatible = "fsl,imx-sc-thermal";
			tsens-num = <6>;
			#thermal-sensor-cells = <1>;
		};
	};

    /**
     * And the platform bus that was done earlier would start from here..
     */
    platform@c000000 {
        ...
    };

### Some Final Touches for Guest Devices

Now we have most of the actual devices setup. Some final modifications for individual devices can be done at the end of the guest device tree configuration. These can be done outside the main node, as we just modify some node properties which are already defined.

    /**
     * For fec1 we need to update the interrupts to match the ones used by guest pass-through.
     * Most of the configuration is exactly the same that was set original imx8 config
     * Qemu starts its pass-through interrupts at 0x70 so lets change that
     * It is not strictly required to remove the possible iommus property but lets do that anyway
     */
    &fec1 {
        compatible = "fsl,imx8qm-fec", "fsl,imx6sx-fec";
        interrupts = <GIC_SPI 0x70 IRQ_TYPE_LEVEL_HIGH>,
                <GIC_SPI 0x71 IRQ_TYPE_LEVEL_HIGH>,
                <GIC_SPI 0x72 IRQ_TYPE_LEVEL_HIGH>,
                <GIC_SPI 0x73 IRQ_TYPE_LEVEL_HIGH>;
        /delete-property/ iommus;
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_fec1>;
        phy-mode = "rgmii-txid";
        phy-handle = <&ethphy0>;
        fsl,magic-packet;
        nvmem-cells = <&fec_mac0>;
        nvmem-cell-names = "mac-address";
        status = "okay";

        mdio {
            #address-cells = <1>;
            #size-cells = <0>;

            ethphy0: ethernet-phy@0 {
                compatible = "ethernet-phy-ieee802.3-c22";
                reg = <0>;
                at803x,eee-disabled;
                at803x,vddio-1p8v;
                qca,disable-smarteee;
                vddio-supply = <&vddio0>;

                vddio0: vddio-regulator {
                    regulator-min-microvolt = <1800000>;
                    regulator-max-microvolt = <1800000>;
                };
            };
        };
    };

    /**
     * Not much to do for clock controller
     * Remove the iommus as it is not needed in guest and turn the device on
     */
    &enet0_lpcg {
        status = "okay";
        /delete-property/ iommus;
    };

    /**
     * Same for our mailbox
     * Update the interrupts to match next available interrupt in Qemu
     */
    &lsio_mu2 {
        compatible = "fsl,imx8-mu-scu", "fsl,imx8qm-mu", "fsl,imx6sx-mu";
        interrupts = <GIC_SPI 0x74 IRQ_TYPE_LEVEL_HIGH>;
        /delete-property/ iommus;
        status = "okay";
    };

    /**
     * In the host devicetree we had some pads which were transferred to guest.
     * There can be found in the original imx8 hosts config.
     **/
    &iomuxc {
        pinctrl-names = "default";
        status = "okay";

        pinctrl_fec1: fec1grp {
            fsl,pins = <
                IMX8QM_COMP_CTL_GPIO_1V8_3V3_ENET_ENETA_PAD		0x000014a0
                IMX8QM_ENET0_MDC_CONN_ENET0_MDC				0x06000020
                IMX8QM_ENET0_MDIO_CONN_ENET0_MDIO			0x06000020
                IMX8QM_ENET0_RGMII_TX_CTL_CONN_ENET0_RGMII_TX_CTL	0x06000020
                IMX8QM_ENET0_RGMII_TXC_CONN_ENET0_RGMII_TXC		0x06000020
                IMX8QM_ENET0_RGMII_TXD0_CONN_ENET0_RGMII_TXD0		0x06000020
                IMX8QM_ENET0_RGMII_TXD1_CONN_ENET0_RGMII_TXD1		0x06000020
                IMX8QM_ENET0_RGMII_TXD2_CONN_ENET0_RGMII_TXD2		0x06000020
                IMX8QM_ENET0_RGMII_TXD3_CONN_ENET0_RGMII_TXD3		0x06000020
                IMX8QM_ENET0_RGMII_RXC_CONN_ENET0_RGMII_RXC		0x06000020
                IMX8QM_ENET0_RGMII_RX_CTL_CONN_ENET0_RGMII_RX_CTL	0x06000020
                IMX8QM_ENET0_RGMII_RXD0_CONN_ENET0_RGMII_RXD0		0x06000020
                IMX8QM_ENET0_RGMII_RXD1_CONN_ENET0_RGMII_RXD1		0x06000020
                IMX8QM_ENET0_RGMII_RXD2_CONN_ENET0_RGMII_RXD2		0x06000020
                IMX8QM_ENET0_RGMII_RXD3_CONN_ENET0_RGMII_RXD3		0x06000020
            >;
        };
    };

With our additional devices also some headers and definitions need to be included at the beginning of the device tree. These additions can be found also from the original i.MX 8 device tree files. See the full device tree below for reference.
 
## Compiling the Device Tree Source to Binary Form

The device trees need to be compiled within the Linux kernel source directory. They depend on some kernel device tree headers and in the host device case—other device tree source files.

 - Full host device tree: [imx8qm-mek_conn-host.dts](imx8qm-mek_conn-host.dts)
 - Full guest device tree: [imx8qm-mek_conn-guest.dts](imx8qm-mek_conn-guest.dts)


### Compiling for Guest

    cpp -nostdinc -I include -I arch  -undef -x assembler-with-cpp \
        arch/arm64/boot/dts/freescale/imx8qm-mek_conn-guest.dts imx8qm-mek_conn-guest.dts.preprocessed; \
        dtc -I dts -O dtb -p 0x1000 imx8qm-mek_conn-guest.preprocessed -o imx8qm-mek_conn-guest.dtb


### Compiling for Host

    cpp -nostdinc -I include -I arch  -undef -x assembler-with-cpp \
        arch/arm64/boot/dts/freescale/imx8qm-mek_conn-host.dts imx8qm-mek_conn-host.dts.preprocessed; \
        dtc -I dts -O dtb -p 0x1000 imx8qm-mek_conn-host.preprocessed -o imx8qm-mek_conn-host.dtb


## Running QEMU with Passthrough Platform Devices

To get passthrough working, i.MX 8 QM needs to be booted using our freshly built hosts **imx8qm-mek_conn-host.dtb** device tree file.

When the system has booted, we need to set up the passedthrough devices for the VFIO driver and start QEMU with devices passed through.

First, the devices need to be setup for VFIO:

    echo vfio-platform  > /sys/bus/platform/devices/5d1d0000.mailbox/driver_override
    echo 5d1d0000.mailbox > /sys/bus/platform/drivers/vfio-platform/bind

    echo vfio-platform > /sys/bus/platform/devices/5b040000.ethernet/driver_override
    echo 5b040000.ethernet > /sys/bus/platform/drivers/vfio-platform/bind

    echo vfio-platform > /sys/bus/platform/devices/5b230000.clock-controller/driver_override
    echo 5b230000.clock-controller > /sys/bus/platform/drivers/vfio-platform/bind

After, QEMU can be started with our devices over the devices.

This is just as an example. It may require a bit of change in other environments.

In this example, the guest kernel image—ext2 rootfs and guest device tree—all use the same filename prefix **imx8qm-mek_conn-guest**.

    qemu-system-aarch64 \
        -M virt,gic-version=host -enable-kvm \
        -cpu host \
        -m 512M \
        -kernel "imx8qm-mek_conn-guest.Image" \
        -drive file="imx8qm-mek_conn-guest.ext2",if=virtio,format=raw -dtb "imx8qm-mek_conn-guest.dtb" \
        -nographic \
        -append "loglevel=7 rootwait root=/dev/vda console=ttyAMA0 earlycon earlyprintk" \
        -device vfio-platform,host=5b230000.clock-controller \
        -device vfio-platform,host=5b040000.ethernet \
        -device vfio-platform,host=5d1d0000.mailbox

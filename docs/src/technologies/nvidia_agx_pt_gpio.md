<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA Jetson AGX Orin: GPIO Passthrough

This document describes the GPIO passthrough implementation on the NVIDIA Jetson AGX Orin board. The purpose of GPIO passthrough is to allow a virtual machine to access GPIO via the available GPIO chips.

## GPIO Chips and Lines

There are two GPIO chips in Nvidia Jetson AGX controlling GPIO,

- _tegra234-gpio_, controlling 164 lines
	- On /dev/gpiochip0, it is also refered to as "gpio_main"
	- (See Appendix A.1)
- _tegra234-gpio-aon_, controlling 32 lines
	- On /dev/gpiochip1, it is also refered to as "gpio_aon"and "gpio_main_aon"
	- (See Appendix A.2)  
	
Each GPIO chip controll a number of GPIO lines. _tegra234-gpio_, controls 164 lines and _tegra234-gpio-aon_ controls 32 lines. Each line is a logical GPIO pin and the line number determines the offset from the GPIO chip's base.

Many of the lines are by default reserved for built in functionality such as regulators, resets, interrupts and camera control (which is using lines for I2S, SPI and other functions) and internal ports such as UART (UARTA or UART1). Some ports are free to use without disrupting the normal operations of Jetson AGX. However reconfiguration of reserved functions is as such possible, but not recommended.
See Appendix A.  
  
Some lines are brought to the pinout of the Jetson 40-pin header. (See Appendix B)
Note that not all pins on the 40-pin header are controlled by the GPIO chips. Some pins have dedicated driver circuitry, thus not available for GPIO nor for GPIO passthrough.

## GPIO Passthrough Host and Guest kernel modules

A kernel driver in Host is acting as a proxy for the Guest VM to operate the GPIO chips and thereby the GPIO lines. This driver is implemented as a built-in kernel module. In Guest the tegra186-gpio kernel driver is hooked to send GPIO request to and receive replies from the /dev/vda device which passes the messages to host-passthrough and the Host's GPIO proxy driver.


## Host Device Tree

To prepare GPIO on the host for the passthrough:

>Add a virtual node to root in the Device Tree using an overlay file. 
   A driver associated to this node will find it using the compatible field.
```
        /plugin/;

        /{
          overlay-name = "GPIO passthrough on host";
          compatible = "nvidia,p3737-0000+p3701-0000\0nvidia,tegra234\0nvidia,tegra23x";

           fragment@0 
           { target-path = "/";
                __overlay__ 
                { gpio_host_proxy 
                    { compatible = "nvidia,gpio-host-proxy";
                      status = "okay";
                    };
                };
            };
        }; 
```


## Guest Device Tree  
  
  The Guest's Device tree serves two purposes.
  - to define the _vda_ passthrough device
  - to select which lines are allowed for passtrough

### Creating the Guest Device Tree

The Guest's Device Tree is based on the device tree extracted from QEMU VM.

>To get the base QEMU device tree, run the following command:

```
    qemu-system-aarch64 -machine virt,accel=kvm,dumpdtb=virt.dtb -cpu host
```
  
  ### Apply an overlay to define the VDA device
The Device Tree defines passthrough memory for the /dev/vda passthrough device with the parameter _virtual-pa_.  
>Add the passthrough device as a root node to the virtual machine's device tree:

```
        /plugin/;

        /{
          overlay-name = "GPIO passthrough on host";
          compatible = "nvidia,p3737-0000+p3701-0000\0nvidia,tegra234\0nvidia,tegra23x";

           fragment@0 
           { target-path = "/";
                __overlay__
                {
                    gpio: gpio {
                        compatible = "nvidia,tegra234-bpmp";
                        virtual-pa = <0x0 0x090c0000>; 
                        status = "okay";
                    }
                };
           };
        };  
```

> The *gpio* node was added to the root node.

### Apply an overlay to define allowed lines for passthrough

The GPIO lines Selected for Passthrough are defined by the Guest's Device Tree

>The Device Tree in the Guest virtual machine will determine which Host GPIO pins are visible and usable for the Guest. This is not the only function of the Guest's Device Tree, also see section Guest Device Tree.

```
     Selecting pins is TODO -- put guest overlay here
```


## Starting the Guest VM

To start the guest VM:

1. Set kernel startup paramters on host:
```
        iommu=pt vfio.enable_unsafe_noiommu_mode=0 vfio_iommu_type1.allow_unsafe_interrupts=1 vfio_platform.reset_required=0
```
2. Set kernel parameters for guest VM in microvm (or QEMU):

```
        rootwait root=/dev/vda console=ttyAMA0
```
3. Set the device tree for guest according (see section Guest Device Tree)

## Testing the passtrough

For testing we need to make the Guest VM use GPIO ports. this can be done either via an UARTA VM console, provided by UARTA passthrough, or by letting the VM's systemd testing service use the ports.  
  
In both cases GPIO port functionality can be verified from the 40-pin header using a logic analysator connected to the 40-head port. (See Appendix C) 

### Using a VM console over UARTA

If you use the built in systemd service in Guest to test the GPIO ports you do not need to follow the steps to enable UARTA. In earier versions of Tegra kernel code, patches for UARTA/BPMP and GPIO were conflicting. Also, it is not certain that that UARTA and GPIO passthrough is shared in the same virtual machine in future versions of Ghaf.

If you are using UARTA as a debug port, stop the microvm@gpio-vm service if it is running. in the VM execute:
```
	sudo systemctl stop microvm@gpio-vm
```

1. Connect the NVIDIA Jetson AGX Orin Debug USB to your PC and open the serial port ttyACM1 at 115200 bps. You can use picocom with this command:

```
	picocom -b 115200 /dev/ttyACM1
```
2. When the guest VM is launched you can see the VM Linux command line in the opened ttyACM1 terminal.
3. A script testing the ports vcan be executed or any other CLI commands that set up and use available ports.

### Using the predefined systemd testing service

A systemd service called microvm@gpio-vm is enabled in the Guest VM and it starts to execute a testing script. It is set to execute the _simple-chardev-test.sh_ bash script.  
  
To verify pin functionality. Connect a logic analyser to pins GPIO08, GPIO09, GPIO27, GPIO35 on the 40-pin Jetson header. (See appendix C.)
  
## Appendixes  
  
### Appendix A.1    
  
Line is the offset from each gpiochoip's base address. Direciton and comment declare defalult use.

####gpiochip0 / tegra234-gpio - 164 lines  
| gpio line | pin | default direction | comment |
| ---------|-------|--------|----------------------------------------------------|
| line   0 | PA.00 | output | consumer=fixed-regulators:regulator@111 |
| line   1 | PA.01 | output | active-low consumer=fixed-regulators:regulator@114 |
| line   2 | PA.02 | output | |
| line   3 | PA.03 | output | consumer=fixed-regulators:regulator@110 |
| line   4 | PA.04 | input | |
| line   5 | PA.05 | input | |
| line   6 | PA.06 | input | |
| line   7 | PA.07 | input | |
| line   8 | PB.00 | input | |
| line   9 | PC.00 | input | |
| line  10 | PC.01 | input | |
| line  11 | PC.02 | input | |
| line  12 | PC.03 | input | |
| line  13 | PC.04 | input | |
| line  14 | PC.05 | input | |
| line  15 | PC.06 | input | |
| line  16 | PC.07 | input | |
| line  17 | PD.00 | input | |
| line  18 | PD.01 | input | |
| line  19 | PD.02 | input | |
| line  20 | PD.03 | input | |
| line  21 | PE.00 | input | |
| line  22 | PE.01 | input | |
| line  23 | PE.02 | input | |
| line  24 | PE.03 | input | |
| line  25 | PE.04 | input | |
| line  26 | PE.05 | input | |
| line  27 | PE.06 | input | |
| line  28 | PE.07 | input | |
| line  29 | PF.00 | input | |
| line  30 | PF.01 | input | |
| line  31 | PF.02 | input | |
| line  32 | PF.03 | input | |
| line  33 | PF.04 | input | |
| line  34 | PF.05 | input | |
| line  35 | PG.00 | input | active-low consumer=force-recovery |
| line  36 | PG.01 | input | consumer=temp-alert |
| line  37 | PG.02 | input | active-low consumer=sleep |
| line  38 | PG.03 | output | |
| line  39 | PG.04 | input | |
| line  40 | PG.05 | input | |
| line  41 | PG.06 | input | |
| line  42 | PG.07 | input | consumer=cd |
| line  43 | PH.00 | input | GPIO35 |
| line  44 | PH.01 | output | |
| line  45 | PH.02 | input | |
| line  46 | PH.03 | output | consumer=camera-control-output-low |
| line  47 | PH.04 | output | consumer=fixed-regulators:regulator@105 |
| line  48 | PH.05 | output | |
| line  49 | PH.06 | output | consumer=camera-control-output-low |
| line  50 | PH.07 | input | I2S2_CLK |
| line  51 | PI.00 | input | I2S_SDIN |
| line  52 | PI.01 | input | I2S_SDOUT |
| line  53 | PI.02 | input | I2S_FS |
| line  54 | PI.03 | input | |
| line  55 | PI.04 | input | |
| line  56 | PI.05 | input | |
| line  57 | PI.06 | input | |
| line  58 | PJ.00 | input | |
| line  59 | PJ.01 | input | |
| line  60 | PJ.02 | input | |
| line  61 | PJ.03 | input | |
| line  62 | PJ.04 | input | |
| line  63 | PJ.05 | input | |
| line  64 | PK.00 | input | |
| line  65 | PK.01 | input | |
| line  66 | PK.02 | input | |
| line  67 | PK.03 | input | |
| line  68 | PK.04 | input | |
| line  69 | PK.05 | output | |
| line  70 | PK.06 | input | |
| line  71 | PK.07 | input | |
| line  72 | PL.00 | input | |
| line  73 | PL.01 | input | |
| line  74 | PL.02 | input | |
| line  75 | PL.03 | input | |
| line  76 | PM.00 | input | |
| line  77 | PM.01 | input | |
| line  78 | PM.02 | input | |
| line  79 | PM.03 | input | |
| line  80 | PM.04 | input | |
| line  81 | PM.05 | input | |
| line  82 | PM.06 | input | |
| line  83 | PM.07 | input | |
| line  84 | PN.00 | input | |
| line  85 | PN.01 | input | GPIO27 |
| line  86 | PN.02 | input | |
| line  87 | PN.03 | output | |
| line  88 | PN.04 | input | |
| line  89 | PN.05 | input | |
| line  90 | PN.06 | input | |
| line  91 | PN.07 | input | |
| line  92 | PP.00 | input | |
| line  93 | PP.01 | input | |
| line  94 | PP.02 | input | |
| line  95 | PP.03 | input | |
| line  96 | PP.04 | input | GPIO17 |
| line  97 | PP.05 | input | |
| line  98 | PP.06 | input | |
| line  99 | PP.07 | input | |
| line 100 | PQ.00 | input | |
| line 101 | PQ.01 | output | consumer=fixed-regulators:regulator@106 |
| line 102 | PQ.02 | input | |
| line 103 | PQ.03 | input | |
| line 104 | PQ.04 | output | |
| line 105 | PQ.05 | input | |
| line 106 | PQ.06 | input | MCLK05 |
| line 107 | PQ.07 | input | |
| line 108 | PR.00 | input | GPIO32 |
| line 109 | PR.01 | input | |
| line 110 | PR.02 | input | |
| line 111 | PR.03 | input | |
| line 112 | PR.04 | input | UART1_RTS |
| line 113 | PR.05 | input | UART1_CTS |
| line 114 | PX.00 | input | |
| line 115 | PX.01 | input | |
| line 116 | PX.02 | input | |
| line 117 | PX.03 | input | |
| line 118 | PX.04 | input | |
| line 119 | PX.05 | input | |
| line 120 | PX.06 | input | |
| line 121 | PX.07 | input | |
| line 122 | PY.00 | output | |
| line 123 | PY.01 | output | consumer=phy_reset |
| line 124 | PY.02 | output | |
| line 125 | PY.03 | input | consumer=interrupt |
| line 126 | PY.04 | input | consumer=interrupt |
| line 127 | PY.05 | input | | |
| line 128 | PY.06 | input | |
| line 129 | PY.07 | input | |
| line 130 | PZ.00 | output | |
| line 131 | PZ.01 | input | |
| line 132 | PZ.02 | input | |
| line 133 | PZ.03 | input | SPI1_MOSI_SCK |
| line 134 | PZ.04 | input | SPI1_MOSI |
| line 135 | PZ.05 | input | SPI1_MOSI |
| line 136 | PZ.06 | input | SPI1_CS0_N |
| line 137 | PZ.07 | input | SPI1_CS1_N |
| line 138 | PAC.00 | output | consumer=camera-control-output-low |
| line 139 | PAC.01 | output | consumer=camera-control-output-low |
| line 140 | PAC.02 | output | |
| line 141 | PAC.03 | input | |
| line 142 | PAC.04 | input | |
| line 143 | PAC.05 | input | consumer=interrupt |
| line 144 | PAC.06 | input | |
| line 145 | PAC.07 | output | consumer=fixed-regulators:regulator@115 |
| line 146 | PAD.00 | input | |
| line 147 | PAD.01 | input | |
| line 148 | PAD.02 | input | |
| line 149 | PAD.03 | input | |
| line 150 | PAE.00 | input | |
| line 151 | PAE.01 | input | |
| line 152 | PAF.00 | input | |
| line 153 | PAF.01 | input | |
| line 154 | PAF.02 | input | |
| line 155 | PAF.03 | input | |
| line 156 | PAG.00 | input | |
| line 157 | PAG.01 | input | |
| line 158 | PAG.02 | input | |
| line 159 | PAG.03 | input | |
| line 160 | PAG.04 | input | |
| line 161 | PAG.05 | input | |
| line 162 | PAG.06 | input | |
| line 163 | PAG.07 | input | |

### Appendix A.2    

Line is the offset from each gpiochoip's base address. Direciton and comment declare defalult use.

####gpiochip1 / tegra234-gpio-aon - 32 lines:
| gpio line | pin | default direction | comment |
| ---------|-------|--------|----------------------------------------------------|
| line   0 | PAA.00 | input | |
| line   1 | PAA.01 | input | |
| line   2 | PAA.02 | input | |
| line   3 | PAA.03 | input | |
| line   4 | PAA.04 | input | |
| line   5 | PAA.05 | input | |
| line   6 | PAA.06 | input | |
| line   7 | PAA.07 | input | |
| line   8 | PBB.00 | input | GPIO9 |
| line   9 | PBB.01 | input | GPIO8 |
| line  10 | PBB.02 | input | |
| line  11 | PBB.03 | output | |
| line  12 | PCC.00 | input | |
| line  13 | PCC.01 | input | |
| line  14 | PCC.02 | output | consumer=fixed-regulators:regulator@116 |
| line  15 | PCC.03 | input | |
| line  16 | PCC.04 | input | |
| line  17 | PCC.05 | input | |
| line  18 | PCC.06 | input | |
| line  19 | PCC.07 | input | |
| line  20 | PDD.00 | input | |
| line  21 | PDD.01 | input | |
| line  22 | PDD.02 | input | |
| line  23 | PEE.00 | input | |
| line  24 | PEE.01 | input | |
| line  25 | PEE.02 | input | |
| line  26 | PEE.03 | input | |
| line  27 | PEE.04 | input | active-low consumer=power-key |
| line  28 | PEE.05 | input | |
| line  29 | PEE.06 | input | |
| line  30 | PEE.07 | input | |
| line  31 | PGG.00 | input | |

### Appendix B  
  
#### Jetson AGX Orin J30 GPIO Expansion Header pinout

|Line|Sysfs GPIO| Connector Label | Description  |  More         | Pin  || Pin  | Connector Label    | Description   | More   |Line|Sysfs GPIO|  
|----|----------|-----------------|--------------|---------------|------||------|--------------------|---------------|--------|----|----------|
|    |          |	3.3 VDC       | Power        | 1A max        | **1**|| **2**| 5.0 VDC            | Power         | 1A max |    |          | 
|    |          |I2C5_DAT|General I2C5 Data| 1.8/3.3V, I2C Bus 8 | **3**|| **4**| 5.0 VDC            | Power         | 1A max |    |          |
|    | | 2C_GP5_CLK | General I2C #5 Clock | 1.8/3.3V, I2C Bus 8 | **5**|| **6**| GND                |               |        |    |          |
|106 | gpio454  |  MCLK05   | Audio Master Clock | 1.8/3.3V      | **7**|| **8**| UART1_TX           | UART #1       |Transmit|    |          |
|    |          |  GND            |              |               |**9 **||**10**| UART1_RX           | UART #1       |Receive |    |          |
|112 | gpio460  |  UART1_RTS | UART #1 Request to Send |1.8/3.3V |**11**||**12**| I2S2_CLK           | Audio I2S #2  | Clock  | 50 | gpio398  |
|108 | gpio456  | **GPIO32**      | GPIO #32     |               |**13**||**14**| GND                                         |    |          |
|85  | gpio433  | **GPIO27**      | (PWM)        |               |**15**||**16**| **GPIO8**          | GPIO #8       |        | 9  | gpio357  |
|    |          |  3.3 VDC        | Power        | 1A max        |**17**||**18**| **GPIO35**         | (PWM)         |        | 43 | gpio391  |
|135 | gpio483  |  SPI1_MOSI      | SPI #1 | Master Out/Slave In |**19**||**20**| GND                |               |        |    |          |
|134 | gpio482  |  SPI1_MOSI      | SPI #1 | Master In/Slave Out |**21**||**22**| GPIO17             | GPIO #17      |        | 96 | gpio444  | 
|133 | gpio481  |  SPI1_SCK       | SPI #1 | Shift Clock         |**23**||**24**| SPI1_CS0_N         | SPI #1 |Chip Select #0 | 136| gpio484  |
|    |             | GND          |              |               |**25**||**26**| SPI1_CS1_N         | SPI #1 |Chip Select #1 | 137| gpio485  |
|    |             |  I2C2_DAT | General I2C #2 Data | I2C Bus 1 |**27**||**28**| I2C2_CLK | General I2C #2 Clock | I2C Bus 1 |    |          |
|1   | gpio317	   | CAN0_DIN     |CAN #0        | Data In       |**29**||**30**| GND                |               |        |    |          |
|0   | gpio316	   | CAN0_DOUT    |CAN #0        | Data Out      |**31**||**32**| **GPIO9**          | GPIO #9       |        |  8 | gpio324  |
|2   | gpio318	   | CAN1_DOUT    |CAN #1        | Data Out      |**33**||**34**| GND                |               |        |    |          |
|53  | gpio401     | I2S_FS | AUDIO I2S #2 Left/Right | Clock    |**35**||**36**| UART1_CTS          |UART #1 | Clear to Send | 113| gpio461  |
|3   | gpio319	   | CAN1_DIN | CAN #1 Data In    |              |**37**||**38**| I2S_SDIN           | Audio I2S #2  |Data In | 52 | gpio400  |
|    |             |  GND     |                   |              |**39**||**40**| I2S_SDOUT          | Audio I2S #2  |Data Out| 51 | gpio399  |

On I2C bus 1, there are existing devices on 0x08, 0x40, 0x41. These are denoted as UU by i2cdetect
Default Setup

The initial pinmux should set all of the these pins, except for the power, UART RX TX and two I2C busses, to GPIO at boot.
Usage designations

The usages described in the above table is the official NVIDIA suggested pin usage for SFIO functionality. A modified device tree or modification to the appropriate registers is required before using as the described function.
Base GPIO Addresses

    - There are two GPIO bases for the line offset, 316 and 348.
    - First number is the GPIO number (i.e. the line offset) within a GPIO controller , compare to Appendix A.1 and A.2
    - Second ( Sysfs GPIO / gpioXXXX ) is the global Linux GPIO number
    - Pin 15 – When configured as PWM:
        - PWM chip sysfs directory: /sys/devices/3280000.pwm
    - Pin 18 – When configured as PWM:
        - PWM chip sysfs directory: /sys/devices/32c0000.pwm
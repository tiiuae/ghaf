#! /usr/bin/env bash
# shellcheck shell=bash
# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Notes:
#     1. This script needs to run on a nix-enabled system, with either internet access or packages installed
#     2. The script uses lspci and dmidecode to detect system information and hardware devices, using simple key words
#     3. The host this script runs on needs to be able to detect all hardware, e.g., no passthrough should be enabled
#     4. Do not attach external devices when running this script
#     5. The script generates commented-out sections for some input devices, which need to be manually selected as many of them need to stay in the host
#     6. Do NOT rely fully on the output of this script; especially for kernel modules and parameters!
#     7. Use the hardware dump generated with the '-e' option to inspect the hardware and manually adjust the configuration file
#     8. If you copied this script, include the following:
#         #! /usr/bin/env nix-shell
#         #! nix-shell -i bash -p pciutils dmidecode usbutils alejandra

usage() {
    cat <<EOF
A simple shell script (bash) to detect hardware parameters and write the results to a nix configuration file.
This file can be used to build a Ghaf-based platform.

Usage: hardware-scan [OPTIONS]

Options:
  -s | --sys           Detect system name, sku, and auto-generate a configuration file name
  -p | --pci           Detect PCI devices with a search pattern (grep -i)
  -n | --net           Detect network devices for passthrough usage with auto-search
  -g | --gpu           Detect GPU devices for passthrough usage with auto-search
  -a | --audio         Detect sound devices for passthrough usage with auto-search
  -u | --usb           Detect USB devices for passthrough usage
  -d | --disk          Detect disks to use
  -i | --input         Detect misc input devices for passthrough usage (excluding keyboard, mouse, touchpad)
  -e | --ext           Dump hardware info for later review (lspci, lsusb, dmidecode, etc.) into hwinfo/. Overwrites existing files.
  -h | --help          This help message

By default, the script runs [ -s -n -g -a -i -u -d -e ] and writes the configuration file.
Running the script with options, you can pipe the output into a desired file (e.g., hardware-scan -p > pci_info.txt).
EOF
}

set +xo pipefail

# Global Variables
CONFIG_FILE="" # name is auto-generated from system information (-y, -a)
system_name=""
system_sku=""
declare -A pci_devices=()
declare -A kernel_modules=()
misc_devlinks=()
misc_attr_names=()
usb_devices=()
disk=""
host_blacklist=""

# Default device groups
NET_ID_1="wlp0s5f"
NET_ID_2="eth"
GPU_ID="gpu"
SND_ID="snd"

# Default entries
pci_devices[$NET_ID_1]=""
pci_devices[$NET_ID_2]=""
pci_devices[$GPU_ID]=""
pci_devices[$SND_ID]=""
kernel_modules[$NET_ID_1]=""
kernel_modules[$NET_ID_2]=""
kernel_modules[$GPU_ID]=""
kernel_modules[$SND_ID]=""

# Detecting system information via dmidecode
detect_system_info() {
    system_manufacturer=$(sudo dmidecode -s system-manufacturer)
    system_version=$(sudo dmidecode -s system-version)
    system_product_name=$(sudo dmidecode -s system-product-name)
    system_sku_number=$(sudo dmidecode -s system-sku-number)
    system_name="$system_manufacturer $system_version"
    system_sku="$system_sku_number $system_product_name"
    CONFIG_FILE="$system_name.nix"
    CONFIG_FILE=${CONFIG_FILE// /-}
    CONFIG_FILE=${CONFIG_FILE,,}
    if $verbose; then
        echo "System: $system_name"
        echo "SKU: $system_sku"
    fi
}

### PCI DEVICE DETECTION ###

add_pci_device () {

    # Parse input params
    local pci_device="$1"
    local device_group_name="$2"
    local group_num="$3"
    local devices=()
    local drivers=""
    local modules=""

    # Find all devices in the IOMMU group
    pci_address=$(echo "$pci_device" | awk '{print $1}')
    iommu_group=$(lspci -vns "$pci_address" | grep "IOMMU group" | awk -F "IOMMU group " '{print $2}')
    iommu_path="/sys/kernel/iommu_groups/$iommu_group"
    readarray -t iommu_devices <<< "$(find "$iommu_path" -type l | awk -F "$iommu_path/devices/" '{print $2}')"

    # Add entries for each device in the IOMMU group
    for i in "${!iommu_devices[@]}"; do

        # Fetch info
        address=${iommu_devices[$i]}
        name=$(lspci -s "$address" | cut -d " " -f 2-)
        vendor_id=$(lspci -mmns "$address" | awk '{print $3}')
        product_id=$(lspci -mmns "$address" | awk '{print $4}')
        drv=$(lspci -nnks "$address" | grep "Kernel driver in use:" | awk -F ": " '{print $2}' | tr -d '[:space:]')
        mods=$(lspci -nnks "$address" | grep "Kernel modules:" | awk -F ": " '{print $2}' | tr -d '[:space:]')

        # Check if device is already passed through
        if echo "${pci_devices[*]}" | grep -q "$address"; then
            echo -e "\n# Error: Cannot add $pci_address to $device_group_name$group_num: already passed through."
            echo "# Device $pci_address and $address are in the same IOMMU group $iommu_group:"
            for j in "${!iommu_devices[@]}"; do echo -n "# "; lspci -s "${iommu_devices[$j]}"; done
            echo -e "# Skipping passthrough of device $pci_address\n"
            return 0
        fi

        # Create device name and entry
        local n=""; if [ "${#iommu_devices[@]}" -gt 1 ]; then n="-$i"; fi
        device_name="$device_group_name$group_num$n"
        devices+=("$(cat << EOF
{
    # $name
    name = "$device_name";
    path = "$address";
    vendorId = $vendor_id;
    productId = $product_id;
    # Detected kernel driver: $drv
    # Detected kernel modules: $mods
}
EOF
)")
        drivers="$drivers,$drv"
        modules="$modules,$mods"
    done

    if $verbose; then
        echo -e "Device entry: \n${devices[*]}"
    fi

    modules=${modules#','}
    modules=$(echo "$modules" | tr ',' '\n' | sort -u | tr '\n' ',')
    modules=${modules%','}

    local modules_to_load=()
    IFS=','
    for elem in $modules; do
        if [ -n "$elem" ]; then modules_to_load+=("\"$elem\""); fi
    done
    IFS=

    # Add detected devices and kernel modules to global arrays
    pci_devices["$device_group_name"]="${devices[*]}"
    kernel_modules["$device_group_name"]="${modules_to_load[*]}"

    # Add kernel modules to host blacklist
    if [ "${modules}" != "" ]; then
        host_blacklist="$host_blacklist,$modules"
    fi
    host_blacklist=$(echo "$host_blacklist" | tr ',' '\n' | sort -u | tr '\n' ',')
    host_blacklist=${host_blacklist%','}
    host_blacklist=${host_blacklist#','}
}

detect_pci_devices() {

    # Check if IOMMU is enabled
    if [ -z "$(ls -A /sys/kernel/iommu_groups)" ]; then
        echo "# It seems that the IOMMU groups are not setup (ls /sys/kernel/iommu_groups). Please enable virtualization in the BIOS, and/or pass the respective kernel parameters."
    fi

    # Parse params
    if [ "$#" -eq 0 ]; then
        read -r -p "Enter search pattern for PCI devices: " search_pattern
        read -r -p "Enter group id PCI devices: " group_id
        group_id=${group_id:-"pci"}
    else
        local search_pattern="$1"
        local group_id="$2"
    fi

    # Search for PCI devices
    readarray -t pci_devs <<< "$(lspci -nn | grep -i "$search_pattern")"

    # Select PCI devices
    if [ ${#pci_devs[@]} -ge 1 ] && [ -n "${pci_devs[0]}" ]; then
        local n=0
        for i in "${!pci_devs[@]}"; do
            read -r -p "Select '${pci_devs[$i]}' for passthrough? [Y/n] " answer
            answer=${answer:-Y}
            case $answer in
                [Yy]* ) add_pci_device "${pci_devs[$i]}" "$group_id" "$n"; n=$((n+1)); continue;;
                [Nn]* ) continue;;
                * ) echo "Please answer yY or nN.";;
            esac
        done
    else
        echo "No device found searching for '$search_pattern'."
        return
    fi
}

### INPUT DEVICE DETECTION ###

# Search for input devices using /dev/input/event*
detect_input_devices() {

    local input_events=()

    while IFS= read -r line; do
        input_events+=("$line")
    done <<< "$(ls /dev/input/event*)"

    # Use udevadm to iterate through input_events and determine devices
    for event in "${input_events[@]}"; do
        device_info=$(udevadm info --query=all --name="$event")
        if [[ $device_info =~ ID_INPUT_KEY=1 ]] || [[ $device_info =~ ID_INPUT_SWITCH=1 ]]; then
            misc_devices+=("$event")
        fi
    done

    # Use udevadm to query misc info (INPUT_KEY, INPUT_SWITCH)
    tmp_devs=()
    tmp_names=()
    for event in "${misc_devices[@]}"; do
        read -r -a devlinks <<< "$(udevadm info "$event" | grep "DEVLINKS" | awk -F "=" '{print $2}')"
        misc_attr_name=$(udevadm info -a "$event" | grep "ATTRS{name}" | awk -F "==" '{print $2}' | tr -d '\n')
        tmp_names+=("$misc_attr_name");
        for dev in "${devlinks[@]}"; do tmp_devs+=("$dev"); done;
    done

    # Remove duplicates
    for elem in "${tmp_names[@]}"; do
        if [[ ! " ${misc_attr_names[*]} " =~ $elem ]]; then
            misc_attr_names+=("$elem")
        fi
    done
    for elem in "${tmp_devs[@]}"; do
        if [[ ! " ${misc_devlinks[*]} " =~ $elem ]]; then
            misc_devlinks+=("$elem")
        fi
    done

    if $verbose; then
        echo -e "Miscellaneous device names:\n${misc_attr_names[*]}\n"
        echo -e "Miscellaneous device links:\n${misc_devlinks[*]}\n"
    fi
}

### USB DEVICE DETECTION ###

# Function to create USB device entry
add_usb() {
    usb_device="$1"
    name="$2"

    # Get USB device info
    bus=$(echo "$usb_device" | awk '{print $2}')
    dev=$(echo "$usb_device" | awk '{print $4}' | tr -d ':')
    hostport=$(udevadm info "/dev/bus/usb/$bus/$dev" | grep R: | awk -F "R: " '{print $2}')
    hostbus=${bus//00/}

    # Write USB device entry
    usb_entry=$(cat << EOF
{
    name="$name";
    hostbus="$hostbus";
    hostport="$hostport";
}
EOF
)
    usb_devices+=("$usb_entry")
    if $verbose; then
        echo "USB device: $usb_entry"
    fi
}
# Search for USB devices using lsusb
detect_usb_devices() {
    search_pattern="$1"
    group_id="$2"

    # Detect USB devices
    usb_devs=()
    while IFS= read -r line; do
        usb_devs+=("$line")
    done <<< "$(lsusb | grep -i "$search_pattern")"
    if [ ${#usb_devs[@]} -ge 1 ] && [ "${usb_devs[0]}" != "" ]; then
        local n=0
        for i in "${!usb_devs[@]}"; do
            read -r -p "Select '${usb_devs[$i]}'? [Y/n] " answer
            answer=${answer:-Y}
            case $answer in
                [Yy]* ) add_usb "${usb_devs[$i]}" "$group_id$n"; n=$((n+1)); continue;;
                [Nn]* ) continue;;
                * ) echo "Please answer yY or nN.";;
            esac
        done
    fi
}

### DISK DETECTION ###

# Detect disks
detect_disks() {
    echo ""
    lsblk -o NAME,TYPE,SIZE,MODEL -d
    read -r -p "Enter the disk device name (default: nvme0n1): " disk_name
    disk_name=${disk_name:-nvme0n1}
    disk="/dev/$disk_name"
    if $verbose; then
      echo "disks.disk1.device = { $disk }"
    fi
}

### HW INFO & CONFIG FILE ###

# Generate extended hardware info
ext_output() {
    if [ ! -d hwinfo/ ]; then mkdir -p hwinfo/; fi
    lspci -nn >> hwinfo/lspci.txt
    lspci_long=$(sudo lspci -nnvvv)
    echo "$lspci_long" >> hwinfo/lspci-long.txt
    lsusb >> hwinfo/lsusb.txt
    lsusb_v=$(sudo lsusb -v)
    echo "$lsusb_v" >> hwinfo/lsusb-v.txt
    lsusb -t >> hwinfo/lsusb-t.txt
    dmi_info=$(sudo dmidecode)
    echo "$dmi_info" >> hwinfo/dmidecode.txt
    lsblk -o NAME,TYPE,SIZE,MODEL -d > hwinfo/lsblk.txt
    udev_db=$(udevadm info --export-db)
    echo "$udev_db" >> hwinfo/udevadm.txt
    dmesg > hwinfo/dmesg.txt
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" hwinfo/
    fi
    tar -czf hwinfo.tar.gz hwinfo/
    echo "> Extended output files written to hwinfo/ directory."
}

# Write the hardware configuration file
write_file() {
    echo "> Writing hardware configuration file..."
    cat << EOF > "$CONFIG_FILE"
# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
# System name
name = "$system_name";

# List of system SKUs covered by this configuration
skus = [
    "$system_sku"
];

# Host configuration
host = {
    kernelConfig.kernelParams = [
        "intel_iommu=on,sm_on"
        "iommu=pt"
        "acpi_backlight=vendor"
        "acpi_osi=linux"
        #"module_blacklist=$host_blacklist"
    ];
};

# Input devices
input = {
    misc = {
        name = [
            # ${misc_attr_names[@]}
        ];
        evdev = [
            # ${misc_devlinks[@]}
        ];
    };
};

# Main disk device
disks = {
    disk1.device = "$disk";
};

# Network devices for passthrough to netvm
network = {
    pciDevices = [
        ${pci_devices[$NET_ID_1]}
        ${pci_devices[$NET_ID_2]}
    ];
    kernelConfig = {
        # Kernel modules are indicative only, please investigate with lsmod/modinfo
        stage1.kernelModules = [];
        stage2.kernelModules = [
            ${kernel_modules[$NET_ID_1]}
            ${kernel_modules[$NET_ID_2]}
        ];
        kernelParams = [];
    };
};

# GPU devices for passthrough to guivm
gpu = {
    pciDevices = [${pci_devices[$GPU_ID]}];
    kernelConfig = {
        # Kernel modules are indicative only, please investigate with lsmod/modinfo
        stage1.kernelModules = [
            ${kernel_modules[$GPU_ID]}
        ];
        stage2.kernelModules = [];
        kernelParams = [
            "earlykms"
        ];
    };
};

# Audio device for passthrough to audiovm
audio = {
    pciDevices = [
        ${pci_devices["$SND_ID"]}
    ];
    kernelConfig = {
        # Kernel modules are indicative only, please investigate with lsmod/modinfo
        stage1.kernelModules = [];
        stage2.kernelModules = [
            ${kernel_modules[$SND_ID]}
        ];
        kernelParams = [];
    };
};

# USB devices for passthrough
usb = {
    internal = [${usb_devices[@]}];
    external = [
        # Add external USB devices here
    ];
};
}
EOF
    echo "> File written: $CONFIG_FILE"
}

### MAIN ###
echo "> Running hardware detection tool..."

# Default options
verbose=true
if [ $# -eq 0 ]; then
    set -- "-s" "-n" "-g" "-a" "-i" "-u" "-d"
    verbose=false
fi

# Run commands
for cmd in "$@"; do
case $cmd in
    -s | --sys)
        echo "> Scanning system information..."
        detect_system_info
        continue
        ;;
    -n | --network)
        echo "> Scanning network PCI devices..."
        detect_pci_devices "network" $NET_ID_1
        detect_pci_devices "ethernet" $NET_ID_2
        continue
        ;;
    -g | --gpu)
        echo "> Scanning GPU PCI devices..."
        detect_pci_devices "vga" $GPU_ID
        continue
        ;;
    -a | --audio)
        echo "> Scanning audio PCI devices..."
        detect_pci_devices "audio" $SND_ID
        continue
        ;;
    -p | --pci)
        echo "> Scanning PCI devices..."
        detect_pci_devices
        continue
        ;;
    -i | --input)
        echo "> Scanning input devices..."
        detect_input_devices
        continue
        ;;
    -u | --usb)
        echo "> Scanning USB devices..."
        detect_usb_devices "cam" "cam"
        detect_usb_devices "fingerprint\|fprint\|biometric" "fpr"
        detect_usb_devices "gps\|gnss" "gps"
        continue
        ;;
    -d | --disk)
        echo "> Scanning disk devices..."
        detect_disks
        continue
        ;;
    -e | --ext)
        echo "> Searching for more hardware info..."
        ext_output
        continue
        ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
        usage
		exit 1
		;;
	esac
done

if ! $verbose; then
    write_file
    echo "> Searching for more hardware info..."
    ext_output
    exit 0
fi

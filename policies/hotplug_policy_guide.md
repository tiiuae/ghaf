# USB Hotplug Policy Specification

This document explains the structure and semantics of the hotplug\_rules configuration used to control USB device passthrough to virtual machines (VMs) based on identifiers like vendor/product ID, device class, and interface-level metadata.

## **Policy Sections**

### **Denylist (denylist)**

#### **Purpose:**

Blocks specific USB devices from being passed to any VM.
Takes precedence over any other rules.

**Format:**

```
"vendor_id": ["product_id1", "product_id2"],
"~vendor_id": ["product_id3"]
```

**vendor\_id, product\_id:**
4-digit hex strings prefixed with 0x (e.g., "0x1234")

**~vendor\_id:**
Inverted rule — all products from this vendor are blocked except those listed.

**Example:**

```
"denylist": {
  "0xbadb": ["0xdada"],
  "~0xbabb": ["0xcaca"]
}
```

### **Allowlist (allowlist)**

#### **Purpose:**

Explicitly allows devices (based on vendor/product) to be attached to one or more VMs.

**Format:**

```
"vendor_id:product_id": ["vm1", "vm2"],
"vendor_id:*": ["vm1"]
```

*   wildcard allows all products from the vendor.

**Example:**

```
"allowlist": {
  "0x0b95:0x1790": ["net-vm"],
  "0x1234:*": ["admin-vm"]
}
```

### **Classlist (classlist)**

#### **Purpose:**

Allows devices based on USB class, subclass, and protocol values.

**Format:**

```
"class:subclass:protocol": ["vm1", "vm2"]
```

Each of class, subclass, and protocol must be 2-digit hex with 0x prefix.
You may use \* as a wildcard for subclass or protocol.

**Example:**

```
"classlist": {
  "0x01:*:*": ["audio-vm"],
  "0x03:*:0x01": ["gui-vm"],
  "0x03:*:0x02": ["gui-vm"],
  "0x08:0x06:*": ["gui-vm"],
  "0x0b:*:*": ["gui-vm"],
  "0x11:*:*": ["gui-vm"],
  "0x02:06:*": ["net-vm"],
  "0x0e:*:*": ["chrome-vm"]
}
```

### **Static Devices (static\_devices)**

#### **Purpose:**

Declares known USB devices that are always allowed on specific VMs, regardless of hotplug detection.

**Format:**

```
[
  {
    "name": "device-name",
    "vendorId": "xxxx",
    "productId": "yyyy",
    "vms": ["vm1", "vm2"]
  }
]
```

**name:** Friendly name for reference/logging.

IDs are 4-digit hex strings (no 0x prefix here).

**Example:**

```
"static_devices": [
  {
    "name": "crazyradio1",
    "vendorId": "1915",
    "productId": "0101",
    "vms": ["gui-vm"]
  },
  {
    "name": "crazyflie0",
    "vendorId": "0483",
    "productId": "5740",
    "vms": ["test-vm"]
  }
]
```
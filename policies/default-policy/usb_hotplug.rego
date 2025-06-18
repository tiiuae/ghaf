
package usb_hotplug
import future.keywords.in


lenovo = data.lenovo
dell = data.dell.denylist
# Rule to populate the set of allowed VMs for the input device.
allowed_vms = vms if {
    # Ensure required input fields are present
    input.class
    input.subclass
    input.protocol
    input.vendor_id
    input.product_id

    denylist = data.hotplug_rules.denylist
    allowlist = data.hotplug_rules.allowlist
    class_rules = data.hotplug_rules.classlist
    #vm_device_filter = data.hotplug_rules.device_filter
    # Check if the device is denied
    not denied(denylist, input.vendor_id, input.product_id)
    # Check if the device is mapped to a specific VM
    device_key_0 := sprintf("%s:%s", [input.vendor_id, input.product_id])
    device_key_1 := sprintf("%s:*", [input.vendor_id])
    wl_vms = array.concat(lookup(allowlist, device_key_0), lookup(allowlist, device_key_1))
    
    # Based on class, subclass, and protocol find list VMs which can access it 
    class_key_0 := sprintf("%s:%s:%s", [input.class, input.subclass, input.protocol])
    class_key_1 := sprintf("%s:%s:*", [input.class, input.subclass])
    class_key_2 := sprintf("%s:*:%s", [input.class, input.protocol])
    class_key_3 := sprintf("%s:*:*", [input.class])
    cl_01_vms = array.concat(lookup(class_rules, class_key_0), lookup(class_rules, class_key_1))
    cl_23_vms = array.concat(lookup(class_rules, class_key_2), lookup(class_rules, class_key_3))
	  cl_vms = array.concat(cl_01_vms, cl_23_vms)

    # Merge VMs from all above rules
	  arr_vms = array.concat(wl_vms, cl_vms)
    unique_vms_set := {element | element := arr_vms[_]}
    
    # Filter any VM if it is disabled by the VM
    # vms = filter_vms(vm_device_filter, unique_vms_set, device_key_0, device_key_1)
    vms = unique_vms_set
} else = []


lookup(allowlist, key) = vms if {
    some vm_list in [allowlist[key]]
    vms = vm_list
} else = []

allowed_in_denylist(denylist, vendor_id, product_id) = true if {
    neg_vendor := sprintf("~%s", [vendor_id])
    vendor_allowlist = lookup(denylist, neg_vendor)
    product_id == vendor_allowlist[_]
}

denied(denylist, vendor_id, product_id) = true if {
    vendor_denylist = lookup(denylist, vendor_id)
    vendor_denylist[_] == product_id
} else = false if {
    neg_vendor := sprintf("~%s", [vendor_id])
    vendor_allowlist = lookup(denylist, neg_vendor)
    count(vendor_allowlist) == 0
} else = false if {
    neg_vendor := sprintf("~%s", [vendor_id])
    vendor_allowlist = lookup(denylist, neg_vendor)
    product_id == vendor_allowlist[_]
} else = true 

is_vm_filtered(vm_device_filter, vm, device_key_0, device_key_1) = true if {
    devices = vm_device_filter[vm]
    device_key_0 == devices[_]
} else = true if {
	devices = vm_device_filter[vm]
    device_key_1 == devices[_]
} else = false

filter_vms(vm_device_filter, sorted_vms, key0, key1) = filtered_vms if {
    filtered_vms := [
        vm |
        some vm in sorted_vms
        not is_vm_filtered(vm_device_filter, vm, key0, key1)
    ]
}

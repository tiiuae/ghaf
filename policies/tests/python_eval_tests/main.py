import json

enable_print = 0


def lookup(whitelist: dict, key: any) -> list:
    return whitelist.get(key, [])


def blacklisted(blacklist: dict, vendor_id: any, product_id: any) -> bool:
    blacklisted_products = blacklist.get(vendor_id)
    if blacklisted_products is not None:
        return product_id in blacklisted_products
    else:
        neg_vendor = f"~{vendor_id}"
        whitelisted_products = blacklist.get(neg_vendor)
        if whitelisted_products is not None:
            return product_id not in whitelisted_products
        else:
            return False


def is_vm_filtered(
    vm_device_filter: dict, vm: any, device_key_0: any, device_key_1: any
) -> bool:
    devices = vm_device_filter.get(vm, [])
    if device_key_0 in devices:
        return True

    if device_key_1 in devices:
        return True

    return False


def filter_vms(vm_device_filter: dict, sorted_vms: list, key0: any, key1: any) -> list:
    filtered_vms = [
        vm for vm in sorted_vms if not is_vm_filtered(vm_device_filter, vm, key0, key1)
    ]

    return filtered_vms


def get_allowed_vms(
    json_data,
    device_class: int,
    subclass: int,
    protocol: int,
    vendor_id: int,
    product_id: int,
):
    result = json_data
    blacklist = result.get("denylist", [])
    whitelist = result.get("allowlist", [])
    class_rules = result.get("classlist", {})

    # Check if the device is blacklisted
    if blacklisted(blacklist, vendor_id, product_id):
        return []

    # Check if the device is mapped to a specific VM
    device_key_0 = f"{vendor_id}:{product_id}"
    device_key_1 = f"{vendor_id}:*"
    wl_vms = lookup(whitelist, device_key_0) + lookup(whitelist, device_key_1)

    # Based on class, subclass, and protocol find list VMs which can access it
    class_key_0 = f"{device_class}:{subclass}:{protocol}"
    class_key_1 = f"{device_class}:{subclass}:*"
    class_key_2 = f"{device_class}:*:{protocol}"
    class_key_3 = f"{device_class}:*:*"
    cl_01_vms = lookup(class_rules, class_key_0) + lookup(class_rules, class_key_1)
    cl_23_vms = lookup(class_rules, class_key_2) + lookup(class_rules, class_key_3)
    cl_vms = cl_01_vms + cl_23_vms

    # Merge VMs from all above rules
    arr_vms = wl_vms + cl_vms
    unique_vms_set = list(set(arr_vms))

    return unique_vms_set


def compare_results(list1, list2):
    if len(list1) == len(list2):
        for elm in list1:
            if elm not in list2:
                return "❌ FAIL"
        return "✅ PASS"
    return "❌ FAIL"


def remove_comments(json_as_string):
    result = ""
    for line in json_as_string.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Remove inline comment
        code_part = line.split("#", 1)[0].rstrip()
        if code_part:
            result += code_part + "\n"
    return result


def run_test(
    test_id,
    rules,
    device_class,
    subclass,
    vendor_id,
    product_id,
    protocol,
    expected_vms,
):
    vms = get_allowed_vms(
        rules,
        device_class=device_class,
        subclass=subclass,
        vendor_id=vendor_id,
        product_id=product_id,
        protocol=protocol,
    )
    result = compare_results(expected_vms, vms)
    print(
        f"{test_id}: expected: {expected_vms!s:<30} received: {vms!s:<30} Result: {result}"
    )


############TESTS###############

if __name__ == "__main__":
    with open("../../default-policy/usb_hotplug_rules.json") as fp:
        data = json.load(fp)

    rules = data["hotplug_rules"]

    run_test(
        test_id="TEST1",
        rules=rules,
        device_class="0xff",
        subclass="0x01",
        vendor_id="0x0b95",
        product_id="0x1790",
        protocol=0,
        expected_vms=["net-vm"],
    )

    run_test(
        test_id="TEST2",
        rules=rules,
        device_class="0x01",
        subclass="0x02",
        vendor_id="0xdead",
        product_id="0xbeef",
        protocol="0x01",
        expected_vms=["audio-vm"],
    )

    run_test(
        test_id="TEST3",
        rules=rules,
        device_class="0x0e",
        subclass="0x02",
        vendor_id="0x04f2",
        product_id="0xb751",
        protocol="0x01",
        expected_vms=["chrome-vm"],
    )

    run_test(
        test_id="TEST4",
        rules=rules,
        device_class="0x0e",
        subclass="0x02",
        vendor_id="0x04f2",
        product_id="0xb755",
        protocol="0x01",
        expected_vms=["chrome-vm"],
    )

    run_test(
        test_id="TEST5",
        rules=rules,
        device_class="0xe0",
        subclass="0x01",
        vendor_id="0x04f2",
        product_id="0xb755",
        protocol="0x01",
        expected_vms=[],
    )

    run_test(
        test_id="TEST6",
        rules=rules,
        device_class="0xe0",
        subclass="0x01",
        vendor_id="0xbadb",
        product_id="0xdada",
        protocol="0x01",
        expected_vms=[],
    )

    run_test(
        test_id="TEST7",
        rules=rules,
        device_class="0xe0",
        subclass="0x01",
        vendor_id="0xbabb",
        product_id="0xcaca",
        protocol="0x01",
        expected_vms=[],
    )

    run_test(
        test_id="TEST8",
        rules=rules,
        device_class="0xe0",
        subclass="0x01",
        vendor_id="0xbabb",
        product_id="0xb755",
        protocol="0x01",
        expected_vms=[],
    )

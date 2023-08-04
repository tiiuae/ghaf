#! @python3@/bin/python3 -B
"""This is opinionated rewrite of nixos/modules/system/boot/loader/systemd-boot/systemd-boot-builder.py,
as well as re-implement some logic from bootctl tool.

Two main goals:
* Use bootspec JSON as primary source of truth about system
* Be enough close to standard bootctl behavior, to allow local system updates
"""
import argparse
import json
import os
import shutil
import sys

BOOT_ENTRY = """title {title}
version Generation {generation} {description}
linux {kernel}
initrd {initrd}
options {kernel_params}
"""

LOADER_CONF = """timeout 0
default nixos-generation-1.conf
console-mode keep
"""

LOADERS = {
    "x86_64-linux": ("systemd-bootx64.efi", "BOOTX64.efi"),
    "aarch64-linux": ("systemd-bootaa64.efi", "BOOTAA64.efi"),
}

def eprint(*args):
    print(*args, file=sys.stderr)

def mkdir_p(path: str) -> None:
    if os.path.isdir(path):
        return
    eprint(f"Create directory {path}")    
    try:
        os.makedirs(path)
    except OSError as e:
        if e.errno != errno.EEXIST or not os.path.isdir(path):
            raise

def write_file(path, content):
    mkdir_p(os.path.dirname(path))
    eprint(f"Writing {path}")
    with open(path, "w") as f:
        f.write(content)

def ensure_file(name: str) -> None:
    if os.path.exists(name):
        eprint(f"Found required file {name}")
    else:
        eprint(f"Can't find required file {name}")
        sys.exit(1)

def copy_file(src, dst):
    mkdir_p(os.path.dirname(dst))
    eprint(f"Copying {src} to {dst}")
    shutil.copy(src, dst)

def make_efi_name(store_file_path: str, root: str = "/") -> str:
    suffix = os.path.basename(store_file_path)
    store_dir = os.path.basename(os.path.dirname(store_file_path))
    return os.path.join(root, "EFI/nixos/%s-%s.efi" % (store_dir, suffix))

def copy_loader(loader, esp, target_name):
    efi = os.path.join(esp, "EFI")
    copy_file(loader, os.path.join(efi, "systemd", os.path.basename(loader)))
    copy_file(loader, os.path.join(efi, "BOOT", target_name))

def copy_nixos(esp, kernel, initrd, dtb: str = None):
    copy_file(kernel, make_efi_name(kernel, esp))
    copy_file(initrd, make_efi_name(initrd, esp))
    if dtb:
        copy_file(dtb, make_efi_name(dtb, esp))

def write_loader_entry(esp, kernel, initrd, init, kernel_params, label, device_tree=None):
    entry = BOOT_ENTRY.format(kernel=make_efi_name(kernel),
                              initrd=make_efi_name(initrd),
                              init=init,
                              kernel_params=' '.join(kernel_params),
                              description=label,
                              generation=1,
                              title="NixOS")
    if device_tree:
        dt = make_efi_name(device_tree) 
        entry += f"\ndevicetree /{dt}"
    write_file(os.path.join(esp, "loader/entries/nixos-generation-1.conf"), entry)
    write_file(os.path.join(esp, "loader/loader.conf"), LOADER_CONF)
    write_file(os.path.join(esp, "loader/entries.srel"), "type1\n")

def read_bootspec_file(toplevel):
    bootfile = os.path.join(toplevel, "boot.json")
    ensure_file(bootfile)
    with open(bootfile, "r") as boot_json:
        content = json.load(boot_json)
        bootspec = content.get("org.nixos.bootspec.v1")
        if bootspec is None:
            eprint(f"""Can't find "org.nixos.bootspec.v1" in {bootfile}""")
            sys.exit(1)
        return bootspec    

def create_esp_contents(toplevel, output, dtb):
    mkdir_p(output)
    boot = read_bootspec_file(toplevel)
    system = boot["system"]
    (loader, target_loader_filename) = LOADERS.get(system)
    if loader is None:
        eprint(f"Haven't loader for system {system}")
        sys.exit(1)
    loader = os.path.join(toplevel, "systemd/lib/systemd/boot/efi", loader)
    ensure_file(loader)
    copy_loader(loader, output, target_loader_filename)
    copy_nixos(output, boot["kernel"], boot["initrd"], dtb)
    kernel_params = boot["kernelParams"]
    kernel_params.insert(0, "init=" + boot["init"])
    write_loader_entry(output, boot["kernel"], boot["initrd"], boot["init"], kernel_params, boot["label"], dtb)

def main() -> None:
    parser = argparse.ArgumentParser(description="Generate contents of ESP partition")
    parser.add_argument('--toplevel', help='NixOS toplevel directory, contains boot.json')
    parser.add_argument('--output', help='Output directory')
    parser.add_argument('--device-tree', default=None)
    args = parser.parse_args()
    create_esp_contents(args.toplevel, args.output, args.device_tree)

if __name__ == '__main__':
    main()

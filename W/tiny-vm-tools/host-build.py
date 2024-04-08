#!/usr/bin/python3
#
# Copyright (C) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import subprocess

BLACK=30
RED=31
GREEN=32
YELLOW=33
BLUE=34
MAGENTA=35
CYAN=36
WHITE=37

art = """
         .,-;-;-,. /'_\\\\
       _/_/_/_|_\\\\_\\\\) /
     '-<_><_><_><_>=/\\\\
jgs    \\`/_/====/_/-'\\\\_\\\\
        ^^     ^^    ^^
"""

archinfo = {
    "i686": {
        #"container": "cd15c63975fb11ff264c2500fcac9b66ebcd2309e0d74ea7b1ba427750377b67",
        "container": "a2ae6f152f46ed4430a9c4127dec83fec480ab74f95755816663f86bd18b67e3",
        "kerneltarget": "686",
        "kernelargs": "console=ttyS0",
        "qemupkg": "x86",
        "qemutarget": "i386",
        "qemumachine": "pc",
        "qemucpu": "qemu32",
        "qemuassets": [
            "/usr/share/seabios/bios-256k.bin",
            "/usr/share/qemu/linuxboot.bin",
            "/usr/share/qemu/linuxboot_dma.bin",
        ],
        "color": BLUE,
        "banner": """
─╔═══╦═══╦═══╗
─║╔══╣╔═╗║╔══╝
╔╣╚══╣╚═╝║╚══╗
╠╣╔═╗║╔═╗║╔═╗║
║║╚═╝║╚═╝║╚═╝║
╚╩═══╩═══╩═══╝
"""
    },
    "amd64": {
        #"container": "3d72f336b2ee7a4c4a525b766b9d3b95c3c68b2272cf96f88b365855350f1d47",
        "container": "a51a734b35ddc64bcf466ca98db22b796ba35d952995ff74890aa8b1f9c67886",
        "kerneltarget": "amd64",
        "kernelargs": "console=ttyS0",
        "qemupkg": "x86",
        "qemutarget": "x86_64",
        "qemumachine": "pc",
        "qemucpu": "qemu64",
        "qemuassets": [
            "/usr/share/seabios/bios-256k.bin",
            "/usr/share/qemu/linuxboot.bin",
            "/usr/share/qemu/linuxboot_dma.bin",
        ],
        "color": RED,
        "banner": """
────────╔╦═══╦╗─╔╗
────────║║╔══╣║─║║
╔══╦╗╔╦═╝║╚══╣╚═╝║
║╔╗║╚╝║╔╗║╔═╗╠══╗║
║╔╗║║║║╚╝║╚═╝║──║║
╚╝╚╩╩╩╩══╩═══╝──╚╝
"""
    },
    "armhf":  {
        #"container": "dd09cd400f78c4b617b662d567f7cfc0a0326b15f9acab66397b6acaca75b97a",
        "container": "8b663a34fd062c0f426b72eb6b36528568a1e1a687bf82b1d3bb007b05f596d2",
        "kerneltarget": "armmp",
        "kernelargs": "",
        "qemupkg": "arm",
        "qemutarget": "arm",
        "qemumachine": "virt",
        "qemucpu": "cortex-a15",
        "color": GREEN,
        "banner": """
────────╔╗──╔═╗
────────║║──║╔╝
╔══╦═╦╗╔╣╚═╦╝╚╗
║╔╗║╔╣╚╝║╔╗╠╗╔╝
║╔╗║║║║║║║║║║║
╚╝╚╩╝╚╩╩╩╝╚╝╚╝
"""
    },
    "arm64": {
        #"container": "911d2a333f9840e1d154e1a76234a44b6527ce01ca0f4ab562b2b93cd19851a4",
        "container": "ea21828556b6940031d17d9729a028c0c7ee5460c41f83a5a00b966728cdcdb8",
        "kerneltarget": "arm64",
        "kernelargs": "",
        "qemupkg": "arm",
        "qemutarget": "aarch64",
        "qemumachine": "virt",
        "qemucpu": "cortex-a57",
        "color": WHITE,
        "banner": """
────────╔═══╦╗─╔╗
────────║╔══╣║─║║
╔══╦═╦╗╔╣╚══╣╚═╝║
║╔╗║╔╣╚╝║╔═╗╠══╗║
║╔╗║║║║║║╚═╝║──║║
╚╝╚╩╝╚╩╩╩═══╝──╚╝
"""
    },
    "mips64el": {
        #"container": "75344a99047639a8ed43f0b44516acb6618d28f8615608aae5c58c33b075f216",
        "container": "22e147a931c6ad0d71adabfefd0eb0021f7e9b2e0d5857d93e61268ca5606ba4",
        "kerneltarget": "5kc-malta",
        "kernelargs": "console=ttyS0",
        "qemupkg": "mips",
        "qemutarget": "mips64el",
        "qemumachine": "malta",
        "qemucpu": "5KEc",
        "color": MAGENTA,
        "banner": """
──────────╔═══╦╗─╔╗──╔╗
──────────║╔══╣║─║║──║║
╔╗╔╦╦══╦══╣╚══╣╚═╝╠══╣║
║╚╝╠╣╔╗║══╣╔═╗╠══╗║║═╣║
║║║║║╚╝╠══║╚═╝║──║║║═╣╚╗
╚╩╩╩╣╔═╩══╩═══╝──╚╩══╩═╝
────║║
────╚╝
"""
    },
    "ppc64el": {
        #"container": "b72b33901ef0eb2dbefc1c8c3a1d91e3151834106507398826fcf8f6a7e07f1c",
        "container": "742e74c0f54117b2b73e6112a76d18f7a2c22f6c2320f2b2a5be44eb23b117d4",
        "kerneltarget": "powerpc64le",
        "kernelargs": "",
        "qemupkg": "ppc",
        "qemutarget": "ppc64",
        "qemumachine": "pseries",
        "qemucpu": "power9_v2.0",
        "color": YELLOW,
        "banner": """
─────────╔═══╦╗─╔╦╗
─────────║╔══╣║─║║║
╔══╦══╦══╣╚══╣╚═╝║║╔══╗
║╔╗║╔╗║╔═╣╔═╗╠══╗║║║║═╣
║╚╝║╚╝║╚═╣╚═╝║──║║╚╣║═╣
║╔═╣╔═╩══╩═══╝──╚╩═╩══╝
║║─║║
╚╝─╚╝
"""
    },
    "s390x": {
        #"container": "c455376d64c043d8b64ff4f46549c098fa6715d6138db88ac42510b741b33ca9",
        "container": "26f472a4919725ba4bdb5796e1fd609db9d34fa0e175778502f19cc9ea220288",
        "kerneltarget": "s390x",
        "kernelargs": "",
        "qemupkg": "misc",
        "qemutarget": "s390x",
        "qemumachine": "s390-ccw-virtio",
        "qemucpu": "qemu",
        "qemuassets": [
            "/usr/share/qemu/s390-ccw.img"
        ],
        "color": CYAN,
        "banner": """
───╔═══╦═══╦═══╗
───║╔═╗║╔═╗║╔═╗║
╔══╬╝╔╝║╚═╝║║║║╠╗╔╗
║══╬╗╚╗╠══╗║║║║╠╬╬╝
╠══║╚═╝╠══╝║╚═╝╠╬╬╗
╚══╩═══╩═══╩═══╩╝╚╝
"""
    },
}


def qemu_cmd(arch, kernel, initrd, ram):
    qemutarget = archinfo[arch]["qemutarget"]
    qemumachine = archinfo[arch]["qemumachine"]
    qemucpu = archinfo[arch]["qemucpu"]
    kernelargs = archinfo[arch]["kernelargs"]
    return """qemu-system-%(target)s -machine %(machine)s -kernel %(kernel)s -initrd %(initrd)s -append "%(kernelargs)s quiet" -nodefaults -nographic -cpu %(cpu)s -m %(ram)s -serial stdio""" % {
        "target": qemutarget,
        "machine": qemumachine,
        "cpu": qemucpu,
        "kernelargs": kernelargs,
        "kernel": kernel,
        "initrd": initrd,
        "ram": ram,
    }


def make_initrd(arch, next_arch, chain, ram):

    initrdout = "initrd-" + arch
    kernelout = "vmlinux-" + arch

    if chain is not None:
        initrdout += "-" + chain

    container = archinfo[arch]["container"]

    kernelpkg = "linux-image-%s" % archinfo[arch]["kerneltarget"]
    packages = [kernelpkg, "busybox-static", "python3", "cpio"]

    for otherarch in archinfo.keys():
        qemupkg = "qemu-system-%s" % archinfo[otherarch]["qemupkg"]
        packages.append(qemupkg)

    here = os.getcwd()

    dockerfile = "bootstrap-%s.docker" % arch
    with open(dockerfile, "w") as fp:
        print("""
FROM docker.io/library/debian@sha256:%(container)s

RUN apt-get update && \
    rm -f /usr/bin/chfn && \
    cp /bin/true /usr/bin/chfn && \
    apt-get install -y %(packages)s
""" % {
    "container": container,
    "packages": " ".join(packages),
    }, file=fp)

    subprocess.run(["podman", "build", "--tag", "bootstrap-%s" % arch, "-f", dockerfile, "."])

    podmanargs = ["podman", "run", "--rm",
                  "--volume", here + ":/nested", "-it",
                  "bootstrap-%s" % arch,
                  "bash", "/nested/build-nested.sh"]
    print(" ".join(podmanargs))

    with open("doinit.sh", "w") as fp:
        banner = archinfo[arch]["banner"]
        color = archinfo[arch]["color"]
        print("""#!/bin/sh
printf "\\033[40;%(color)sm"
echo "Running in %(arch)s..."
echo
cat <<EOF
%(banner)s
EOF
printf "\\033[0m"
echo
""" % {"banner": banner, "arch": arch, "color": color}, file=fp)

        if next_arch:
            qemutarget = archinfo[next_arch]["qemutarget"]
            qemumachine = archinfo[next_arch]["qemumachine"]
            qemucpu = archinfo[next_arch]["qemucpu"]
            kernelargs = archinfo[next_arch]["kernelargs"]
            print("""echo "Launching %(next_arch)s..."
%(qemu)s
echo "Back in %(arch)s...
"
""" % { "arch": arch, "next_arch": next_arch,
        "qemu": qemu_cmd(next_arch, "/vmlinux", "/initrd", ram) },
                  file=fp)

        print("""
printf "\\033[40;%(color)sm"
cat <<EOF
%(art)s
EOF
printf "\\033[0m"
exit
#exec setsid cttyhack /bin/sh
""" % { "arch": arch, "art": art, "color": color }, file=fp)
    os.chmod("doinit.sh", 0o700)

    args = [
        "--copy", "/nested/doinit.sh=/doinit.sh",
    ]
    if next_arch:
        args.extend(["--copy", "/nested/vmlinux-%s=/vmlinux" % next_arch,
                     "--copy", "/nested/initrd-%s=/initrd" % chain])
        if "qemuassets" in archinfo[next_arch]:
            for asset in archinfo[next_arch]["qemuassets"]:
                args.extend(["--copy", asset + "=" + asset])
        args.append("qemu-system-%s" % archinfo[next_arch]["qemutarget"])

    with open("build-nested.sh", "w") as fp:
        podmanscript = """
#!/bin/sh

set -e
set -v
cp /boot/vmlin* /nested/%(kernelout)s
cd /nested
./make-tiny-image.py --run="sh /doinit.sh" %(args)s
mv tiny-initrd.img /nested/%(initrdout)s
""" % { "packages": " ".join(packages), "arch": arch,
        "args": " ".join(args),
        "initrdout": initrdout,
        "kernelout": kernelout }

        print(podmanscript, file=fp)

    os.chmod("build-nested.sh", 0o700)

    subprocess.run(podmanargs)

    runout = "run-" + arch
    if chain is not None:
        runout += "-" + chain
    runout += ".sh"
    with open(runout , "w") as fp:
        print(qemu_cmd(arch, kernelout, initrdout, 2048), file=fp)
    os.chmod(runout, 0o700)


if False:
    make_initrd("i686", None, None, 0)
    make_initrd("amd64", None, None, 0)
    make_initrd("armhf", None, None, 0)
    make_initrd("arm64", None, None, 0)
    make_initrd("ppc64el", None, None, 0)
    make_initrd("mips64el", None, None, 0)
    make_initrd("s390x", None, None, 0)
    exit

for arch in archinfo.keys():
    for next_arch in archinfo.keys():
        make_initrd(arch, next_arch, next_arch, 256)

def make_nested(archchain):
    prevarch=None
    chain=None
    ram=256
    for arch in archchain:
        make_initrd(arch, prevarch, chain, ram)
        prevarch=arch
        ram += 256
        if chain:
            chain = arch + "-" + chain
        else:
            chain = arch

#make_nested(["arm64", "ppc64el", "s390x", "armhf", "amd64", "i686", "mips64el"])

make_nested(["s390x", "mips64el", "arm64", "amd64"])

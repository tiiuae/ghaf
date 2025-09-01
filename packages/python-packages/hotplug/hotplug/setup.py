# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
from setuptools import find_packages, setup

setup(
    name="hotplug",
    version="1.0",
    packages=find_packages(),
    install_requires=[
        "qemu.qmp",
        "systemd-python",
    ],
    entry_points={
        "console_scripts": [
            "hotplug=hotplug.main:main",
        ],
    },
)

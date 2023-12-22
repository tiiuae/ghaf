#!/usr/bin/env python

# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

from setuptools import find_packages, setup

setup(
    name="gpswebsock",
    version="1.0",
    # Modules to import from other scripts:
    packages=find_packages(),
    # Executables
    scripts=["main.py"],
)

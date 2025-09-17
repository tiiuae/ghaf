# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
from setuptools import find_packages, setup

setup(
    name="ldap-query",
    version="1.0",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "ldap-query=ldap_query.main:main",
        ],
    },
)

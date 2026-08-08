#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
"""Replace the storage-device partitions in NVIDIA's flash XML.

Reads NVIDIA's flash_t234_qspi_{sdmmc,nvme}*.xml, finds the storage
<device> element (sdmmc_user for eMMC boards, nvme for NVMe boards),
replaces all its <partition> children with partitions defined in a
JSON file, and writes the result. This avoids fragile line-count
splicing that breaks when the upstream XML changes.

Usage:
    splice-flash-xml.py [--set PARTITION.FIELD=VALUE]...
                        [--remove-device]
                        [--device-type TYPE]
                        <nvidia-flash.xml> <partitions.json> <output.xml>

The JSON file is a list of partition objects, each with:
    - name (str): partition name attribute
    - type (str): partition type attribute
    - children (dict): child element tag -> text content

The --set flag overrides a child element value for a named partition.
For example: --set APP.size=12345678

The --remove-device flag removes the storage device element entirely
(for QSPI-only flashing where no eMMC/NVMe partitions are needed).

The --device-type flag selects which <device> element to splice into
(default "sdmmc_user"; use "nvme" for NVMe-rootfs boards like the
p3768 Orin NX/Nano devkit).
"""

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def parse_set_value(value: str) -> tuple[str, str, str]:
    """Parse 'PARTITION.FIELD=VALUE' into (partition_name, field, value)."""
    lhs, _, rhs = value.partition("=")
    if not rhs:
        msg = f"--set requires PARTITION.FIELD=VALUE, got: {value!r}"
        raise argparse.ArgumentTypeError(msg)
    part_name, _, field = lhs.partition(".")
    if not field:
        msg = f"--set requires PARTITION.FIELD=VALUE, got: {value!r}"
        raise argparse.ArgumentTypeError(msg)
    return part_name, field, rhs


def splice_partitions(
    flash_xml: Path,
    partitions_json: Path,
    output: Path,
    *,
    overrides: list[tuple[str, str, str]],
    remove_device: bool = False,
    device_type: str = "sdmmc_user",
) -> None:
    """Replace the storage device's partitions in NVIDIA's flash XML."""
    tree = ET.parse(flash_xml)
    root = tree.getroot()

    storage = next(
        (d for d in root.iter("device") if d.get("type") == device_type),
        None,
    )
    if storage is None:
        msg = f"No <device type='{device_type}'> found in {flash_xml}"
        raise ValueError(msg)

    if remove_device:
        # QSPI-only: remove the entire storage device element
        root.remove(storage)
    else:
        # Remove all existing children
        for child in list(storage):
            storage.remove(child)

        partitions: list[dict[str, str | dict[str, str]]] = json.loads(
            partitions_json.read_text()
        )

        # Apply --set overrides
        for part_name, field, value in overrides:
            for part_def in partitions:
                if part_def["name"] == part_name:
                    children = part_def["children"]
                    assert isinstance(children, dict)
                    children[field] = value
                    break
            else:
                msg = f"--set: partition {part_name!r} not found"
                raise ValueError(msg)

        for part_def in partitions:
            part = ET.SubElement(
                storage,
                "partition",
                name=str(part_def["name"]),
                type=str(part_def["type"]),
            )
            part.text = "\n"
            part.tail = "\n"
            children = part_def["children"]
            assert isinstance(children, dict)
            for tag, text in children.items():
                child = ET.SubElement(part, tag)
                child.text = f" {text} "
                child.tail = "\n"

    ET.indent(tree, space="    ")
    # Write without xml_declaration — we prepend it manually to match
    # NVIDIA's original format (no encoding attribute). Some NVIDIA
    # tools choke on encoding='utf-8' in the declaration.
    with open(output, "w") as f:
        f.write('<?xml version="1.0"?>\n')
        tree.write(f, xml_declaration=False, encoding="unicode")
        # Ensure trailing newline — NVIDIA's flash.sh pipes the XML
        # through `while read line` which silently drops the last line
        # if it lacks a newline terminator.
        f.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Splice partition layout into NVIDIA flash XML"
    )
    parser.add_argument("flash_xml", type=Path, help="NVIDIA flash XML template")
    parser.add_argument("partitions_json", type=Path, help="Partition layout JSON")
    parser.add_argument("output", type=Path, help="Output XML path")
    parser.add_argument(
        "--set",
        dest="overrides",
        action="append",
        default=[],
        metavar="PARTITION.FIELD=VALUE",
        help="Override a partition child element value",
    )
    parser.add_argument(
        "--remove-device",
        action="store_true",
        help="Remove the storage device entirely (QSPI-only flash)",
    )
    parser.add_argument(
        "--device-type",
        default="sdmmc_user",
        help="Storage <device> type to splice into (sdmmc_user or nvme)",
    )
    args = parser.parse_args()

    overrides = [parse_set_value(v) for v in args.overrides]

    splice_partitions(
        flash_xml=args.flash_xml,
        partitions_json=args.partitions_json,
        output=args.output,
        overrides=overrides,
        remove_device=args.remove_device,
        device_type=args.device_type,
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
"""Replace the sdmmc_user device partitions in NVIDIA's flash XML.

Reads NVIDIA's flash_t234_qspi_sdmmc*.xml, finds the
<device type="sdmmc_user"> element, replaces all its <partition>
children with partitions defined in a JSON file, and writes the
result. This avoids fragile line-count splicing that breaks when
the upstream XML changes.

Usage:
    splice-flash-xml.py [--set PARTITION.FIELD=VALUE]...
                        [--remove-device]
                        <nvidia-flash.xml> <partitions.json> <output.xml>

The JSON file is a list of partition objects, each with:
    - name (str): partition name attribute
    - type (str): partition type attribute
    - children (dict): child element tag -> text content

The --set flag overrides a child element value for a named partition.
For example: --set APP.size=12345678

The --remove-device flag removes the sdmmc_user device element entirely
(for QSPI-only flashing where no eMMC partitions are needed).
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
) -> None:
    """Replace sdmmc_user partitions in NVIDIA's flash XML with our layout."""
    tree = ET.parse(flash_xml)
    root = tree.getroot()

    sdmmc_user = next(
        (d for d in root.iter("device") if d.get("type") == "sdmmc_user"),
        None,
    )
    if sdmmc_user is None:
        msg = f"No <device type='sdmmc_user'> found in {flash_xml}"
        raise ValueError(msg)

    if remove_device:
        # QSPI-only: remove the entire sdmmc_user device element
        root.remove(sdmmc_user)
    else:
        # Remove all existing children
        for child in list(sdmmc_user):
            sdmmc_user.remove(child)

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
                sdmmc_user,
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
        help="Remove the sdmmc_user device entirely (QSPI-only flash)",
    )
    args = parser.parse_args()

    overrides = [parse_set_value(v) for v in args.overrides]

    splice_partitions(
        flash_xml=args.flash_xml,
        partitions_json=args.partitions_json,
        output=args.output,
        overrides=overrides,
        remove_device=args.remove_device,
    )


if __name__ == "__main__":
    main()

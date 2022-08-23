# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
Setup script configuration
"""

from dataclasses import dataclass


@dataclass
class Config:
    """
    Setup script configuration options.
    """

    metadata_url = "https://zmk.dev/hardware-metadata.json"
    template_url = "https://github.com/zmkfirmware/unified-zmk-config-template.git"
    files_url = "https://raw.githubusercontent.com/zmkfirmware/zmk/main"

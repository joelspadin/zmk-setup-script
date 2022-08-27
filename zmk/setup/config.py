# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
Setup script configuration
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class Config:
    """
    Setup script configuration options.
    """

    repo_path: Optional[Path] = None

    metadata_url = "https://zmk.dev/hardware-metadata.json"
    template_url = "https://github.com/zmkfirmware/unified-zmk-config-template.git"
    files_url = "https://raw.githubusercontent.com/zmkfirmware/zmk/main"

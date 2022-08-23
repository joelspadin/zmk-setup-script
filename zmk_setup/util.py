# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
Miscellaneous utilities
"""
import re
import textwrap
from pathlib import Path
import requests


class StopWizard(Exception):
    """Exception thrown to cancel the wizard"""


def print_block(text: str, trim=False):
    """
    Print a text block. textwrap.dedent() is called on the text before printing
    it, so multiline, indented strings can easily be used.

    :param trim: Trim leading and trailing newlines
    """
    text = textwrap.dedent(text)
    if trim:
        text = text.strip()
    print(text)


def download(url: str, filename: Path | str):
    """
    Fetch a text file from "url" and write it to a file at "filename".
    """
    response = requests.get(url, stream=True, allow_redirects=True)
    response.raise_for_status()

    path = Path(filename).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)

    path.write_text(response.text, encoding="utf-8")


_DIGITS = re.compile(r"(\d+)")


def natural_key(text: str):
    """
    Key function for sorting which is case insensitive and treats
    """
    return [int(s) if _DIGITS.fullmatch(s) else s.lower() for s in _DIGITS.split(text)]

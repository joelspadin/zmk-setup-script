# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
ZMK file functions
"""
import json
from dataclasses import dataclass, field
from typing import Literal, Optional, TypeGuard, TypedDict
import requests
from typing_extensions import NotRequired
from .config import Config
from .menu import show_menu, show_prompt
from .repo import Repo
from .terminal import Color, colorize
from .util import StopWizard, natural_key
from .yaml import YAML


_ACTIONS_YAML = ".github/workflows/build.yml"
_WEST_YAML = "config/west.yml"
_BUILD_YAML = "build.yaml"

Feature = Literal["keys", "display", "encoder", "underglow", "backlight", "pointer"]
Output = Literal["usb", "ble"]


class Board(TypedDict):
    """Metadata for a ZMK board"""

    type: Literal["board"]
    file_format: NotRequired[str]
    id: str
    name: str
    directory: str
    url: NotRequired[str]
    arch: NotRequired[str]
    outputs: NotRequired[list[Output]]
    description: NotRequired[str]
    siblings: NotRequired[list[str]]
    features: NotRequired[list[Feature]]
    exposes: NotRequired[list[str]]


class Shield(TypedDict):
    """Metadata for a ZMK shield"""

    type: Literal["shield"]
    id: str
    name: str
    directory: str
    url: NotRequired[str]
    description: NotRequired[str]
    siblings: NotRequired[list[str]]
    features: NotRequired[list[Feature]]
    exposes: NotRequired[list[str]]
    requires: NotRequired[list[str]]


class Interconnect(TypedDict):
    """Metadata for a ZMK interconnect"""

    type: Literal["interconnect"]
    id: str
    name: str
    directory: str
    url: NotRequired[str]
    description: NotRequired[str]


Keyboard = Board | Shield
Hardware = Keyboard | Interconnect


def check_repo_files(repo: Repo, config: Config):
    """
    Verify that the necessary files are present in the repo,
    and prompt the user to add them if not.
    """

    files = [
        repo.path / _ACTIONS_YAML,
        repo.path / _WEST_YAML,
        repo.path / _BUILD_YAML,
    ]

    if all(f.exists() for f in files):
        return

    print()
    print(colorize("The following required files are missing:", Color.YELLOW))
    for path in files:
        if not path.exists():
            print(colorize(f"- {path.relative_to(repo.path)}", Color.YELLOW))

    print()
    if not show_prompt("Initialize these files?"):
        raise StopWizard()

    repo.fetch(config.template_url)

    for path in files:
        if not path.exists():
            repo.checkout_file("FETCH_HEAD", path)

    repo.commit_changes("Initialize repo from template")


def is_board(hardware: Hardware) -> TypeGuard[Board]:
    """Get whether a hardware entry is a board"""
    return hardware["type"] == "board"


def is_shield(hardware: Hardware) -> TypeGuard[Shield]:
    """Get whether a hardware entry is a shield"""
    return hardware["type"] == "shield"


def is_keyboard(hardware: Hardware) -> TypeGuard[Keyboard]:
    """
    Get whether a hardware entry is a keyboard (a shield or a board that has
    the "keys" feature)
    """
    if is_board(hardware):
        return "keys" in hardware.get("features", [])

    return is_shield(hardware)


def is_controller(hardware: Hardware) -> TypeGuard[Board]:
    """
    Get whether a hardware entry is a controller (a board that isn't a keyboard)
    """
    return is_board(hardware) and not is_keyboard(hardware)


def is_interconnect_compatible(shield: Shield, board: Board):
    """
    Get whether the given shield and board have a compatible interconnect.
    """
    requires = shield.get("requires", [])
    exposes = board.get("exposes", [])
    return all(r in exposes for r in requires)


def is_compatible_controller(shield: Hardware, board: Hardware):
    """
    Get whether the given hardware entries represent a shield and a board which
    is a compatible controller for that shield.
    """
    return (
        is_shield(shield)
        and is_controller(board)
        and is_interconnect_compatible(shield, board)
    )


def get_sibling_ids(hardware: Hardware) -> list[str]:
    """
    Get the list of sibling board/shield IDs for a hardware entry.
    If no siblings are defined, this returns a list with just the given
    hardware ID.
    """
    return hardware.get("siblings", [hardware["id"]])


def is_split(hardware: Hardware):
    """Get whether a hardware entry has multiple parts that must be built"""
    return len(get_sibling_ids(hardware)) > 1


def is_usb_only(hardware: Hardware):
    """Get whether a hardware entry does not support bluetooth"""
    return "ble" not in hardware.get("outputs", [])


@dataclass
class KeyboardSelection:
    """User's selected keyboard and controller (if needed)"""

    keyboard: Keyboard
    controller: Optional[Board] = None
    board_ids: list[str] = field(default_factory=list)
    shield_ids: list[str] = field(default_factory=list)


def select_keyboard(config: Config):
    """
    Prompt the user to select a keyboard and controller (if needed) from the
    list of hardware supported by ZMK.
    """

    def formatter(hardware):
        return hardware["name"]

    print()
    hardware = _get_hardware_list(config)

    keyboards = [x for x in hardware if is_keyboard(x)]
    keyboard = show_menu("Pick a keyboard:", keyboards, formatter)

    if is_board(keyboard):
        return KeyboardSelection(keyboard=keyboard, board_ids=get_sibling_ids(keyboard))

    controllers = [x for x in hardware if is_compatible_controller(keyboard, x)]
    controller = show_menu("Pick an MCU board:", controllers, formatter)

    if is_split(keyboard) and is_usb_only(controller):
        raise StopWizard("Sorry, ZMK does not yet support wired splits")

    return KeyboardSelection(
        keyboard=keyboard,
        controller=controller,
        board_ids=[controller["id"]],
        shield_ids=get_sibling_ids(keyboard),
    )


def _get_hardware_list(config: Config) -> list[Hardware]:
    response = requests.get(config.metadata_url)
    response.raise_for_status()

    hardware = json.loads(response.text)  # type: list[Hardware]
    hardware.sort(key=lambda h: natural_key(h["name"]))

    return hardware


def get_config_file_name(keyboard: Keyboard):
    """Get the name of the .conf file for a keyboard"""
    return keyboard["id"] + ".conf"


def get_keymap_file_name(keyboard: Keyboard):
    """Get the name of the .keymap file for a keyboard"""
    return keyboard["id"] + ".keymap"


def add_to_build_matrix(repo: Repo, selected: KeyboardSelection):
    """Add the selected keyboard to the repo's build.yaml"""
    path = repo.path / "build.yaml"

    yaml = YAML()
    yaml.indent(mapping=2, sequence=4, offset=2)

    data = yaml.load(path)

    if "include" not in data:
        data["include"] = []

    def add_build(item: dict):
        if not item in data["include"]:
            data["include"].append(item)

    for board in selected.board_ids:
        if selected.shield_ids:
            for shield in selected.shield_ids:
                add_build(dict(shield=shield, board=board))
        else:
            add_build(dict(board=board))

    yaml.dump(data, path)

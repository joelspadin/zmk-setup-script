# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
ZMK setup script
"""

from subprocess import CalledProcessError
import sys
import textwrap
from requests.exceptions import HTTPError
from .config import Config
from .menu import StopMenu, show_prompt
from .repo import Repo, select_repo, check_dependencies
from .terminal import Color, colorize
from .util import StopWizard, download, print_block
from .zmk import (
    KeyboardSelection,
    add_to_build_matrix,
    check_repo_files,
    get_config_file_name,
    get_keymap_file_name,
    select_keyboard,
)


def main():
    """Main entry point"""

    config = Config()

    try:
        run_wizard(config)
    except (KeyboardInterrupt, EOFError, StopMenu):
        # User pressed Ctrl+C or otherwise canceled an input prompt
        print("Canceled.")
        sys.exit(1)
    except StopWizard as ex:
        print(ex)
        sys.exit(1)


def run_wizard(config: Config):
    """
    Run the setup wizard
    """
    check_dependencies()

    repo = select_repo(config)

    if repo.has_changes():
        raise StopWizard(
            "You have local changes in this repo. Please commit or stash them first."
        )

    repo.pull()
    check_repo_files(repo, config)

    selected = select_keyboard(config)
    copy_keymap = show_prompt("Copy the stock keymap for customization?")

    print_pending_changes(repo, selected, copy_keymap)

    if not show_prompt("Continue?"):
        raise StopWizard()

    apply_changes(repo, config, selected, copy_keymap)
    commit_and_push_changes(repo, selected)


def print_pending_changes(repo: Repo, selected: KeyboardSelection, copy_keymap: bool):
    """
    Print a message indicating the changes that will be made.
    """
    print("Adding the following to your user config repo:")

    boards = colorize(f"({' '.join(selected.board_ids)})", Color.BLACK)
    shields = colorize(f"({' '.join(selected.shield_ids)})", Color.BLACK)

    if selected.shield_ids:
        print_block(
            f"""
            - Shield:       {selected.keyboard["name"]}  {shields}
            - MCU Board:    {selected.controller["name"]}  {boards}
            """,
            trim=True,
        )
    else:
        print(f"- Board:        {selected.keyboard['name']}  {boards}")

    print_block(
        f"""
        - Copy keymap?: {'Yes' if copy_keymap else 'No'}
        - Repo URL:     {repo.remote_url()}
        """,
        trim=True,
    )
    print()


def apply_changes(
    repo: Repo, config: Config, selected: KeyboardSelection, copy_keymap: bool
):
    """
    Makes the requested changes to the files in the repo
    """
    download_files(repo, config, selected, copy_keymap)

    print("Updating build matrix...")
    add_to_build_matrix(repo, selected)


def download_files(
    repo: Repo, config: Config, selected: KeyboardSelection, copy_keymap: bool
):
    """
    Downloads any keyboard files (keymaps, configs, etc.) that are missing for
    the selected keyboard.
    """
    base_path = repo.path / "config"

    config_name = get_config_file_name(selected.keyboard)
    keymap_name = get_keymap_file_name(selected.keyboard)

    keyboard_files = [config_name]
    if copy_keymap:
        keyboard_files.append(keymap_name)

    for name in keyboard_files:
        dest = base_path / name
        if dest.exists():
            print(f"{name} already exists")
            continue

        print(f"Downloading {name}...")
        url = f"{config.files_url}/{selected.keyboard['directory']}/{name}"
        try:
            download(url, dest)
        except HTTPError as ex:
            # Failed to download the file. Create an empty placeholder file.
            print(ex)
            with dest.open("w"):
                pass


def commit_and_push_changes(repo: Repo, selected: KeyboardSelection):
    """
    Makes a commit and pushes it.
    """
    if not repo.has_changes():
        print("This keyboard is already in the repo. No changes made.")
        return

    print("Committing changes...")
    print()
    repo.commit_changes(f"Add {selected.keyboard['name']}")

    print()
    print(f"Pushing changes to {repo.remote_url()} ...")
    print()

    try:
        repo.push_origin()
    except CalledProcessError as ex:
        error = textwrap.dedent(
            f"""
            {colorize(f'Failed to push to {repo.remote_url()}', Color.RED)}
            Check your repo's URL and try again by running the following commands:
                git remote rm origin
                git remote add origin <PASTE_REPO_URL_HERE>
                git push --set-upstream origin {repo.get_head_ref()}
            """
        )
        raise StopWizard(error) from ex

    print()

    actions_url = repo.actions_url()
    if actions_url:
        print_block(
            f"""\
            {colorize(
                'Success! Your firmware will be available from GitHub Actions at:',
                Color.GREEN,
            )}

                {actions_url}
            """
        )
    else:
        print(colorize("Success!", Color.GREEN))


if __name__ == "__main__":
    main()

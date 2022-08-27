# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
ZMK setup script
"""

import argparse
from pathlib import Path
from subprocess import CalledProcessError
import sys
import textwrap
from requests.exceptions import HTTPError
from .config import Config
from .menu import StopMenu, show_prompt
from .repo import Repo, select_repo, check_dependencies
from .terminal import Color, colorize, enable_vt_mode
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

    parser = argparse.ArgumentParser(
        description="Create a ZMK user config repo and add keyboards to it."
    )
    parser.add_argument(
        "-r",
        "--repo",
        type=Path,
        help="""
            Path to a ZMK user config repo to modify. If this option is not set,
            the current directory is checked to see if it is a Git repo.
            Otherwise, prompts to create a new repo.
            """,
    )
    parser.add_argument(
        "--metadata-url",
        help="""
            URL of a JSON file which lists the supported boards and shields.
            This file contains an array of objects which hold the contents of
            the metadata .yaml files for each board and shield. Each object must
            also have a "directory" member added, which is the relative path to
            the board/shield directory.
            """,
    )
    parser.add_argument(
        "--template-url",
        help="URL of the template repo to use when initializing a new repo.",
    )
    parser.add_argument(
        "--files-url",
        help="""
            Base URL for downloading files from the ZMK repo. Defaults to the
            main ZMK repo. For example, to get files from a GitHub repo, use
            "https://raw.githubusercontent.com/<user>/<repo>/<branch>".
            """,
    )

    config = Config()
    args = parser.parse_args()

    if args.repo:
        config.repo_path = args.repo
    if args.metadata_url:
        config.metadata_url = args.metadata_url
    if args.template_url:
        config.template_url = args.template_url
    if args.files_url:
        config.files_url = args.file_url

    try:
        with enable_vt_mode():
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

    if not repo.is_repo:
        raise StopWizard(f"{repo.path} is not a Git repo.")

    if repo.has_changes():
        raise StopWizard(
            "You have local changes in this repo. Please commit or stash them first."
        )

    repo.pull()
    check_repo_files(repo, config)

    selected = select_keyboard(config)

    print_pending_changes(repo, selected)

    if not show_prompt("Continue?"):
        raise StopWizard()

    apply_changes(repo, config, selected)
    commit_and_push_changes(repo, selected)


def print_pending_changes(repo: Repo, selected: KeyboardSelection):
    """
    Print a message indicating the changes that will be made.
    """
    print("Adding the following to your user config repo:")

    boards = colorize(f"({' '.join(selected.board_ids)})", Color.GRAY)
    shields = colorize(f"({' '.join(selected.shield_ids)})", Color.GRAY)

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

    print(f"- Repo URL:     {repo.remote_url()}")
    print()


def apply_changes(repo: Repo, config: Config, selected: KeyboardSelection):
    """
    Makes the requested changes to the files in the repo
    """
    download_files(repo, config, selected)

    print("Updating build matrix...")
    add_to_build_matrix(repo, selected)


def download_files(repo: Repo, config: Config, selected: KeyboardSelection):
    """
    Downloads any keyboard files (keymaps, configs, etc.) that are missing for
    the selected keyboard.
    """
    base_path = repo.path / "config"

    config_name = get_config_file_name(selected.keyboard)
    keymap_name = get_keymap_file_name(selected.keyboard)

    keyboard_files = [config_name, keymap_name]

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

# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
Git repository functions
"""
import subprocess
from subprocess import Popen, PIPE, STDOUT
from pathlib import Path
from typing import Optional

from .config import Config
from .menu import show_menu
from .terminal import Color, colorize
from .util import StopWizard, prefix_output, print_block


class Repo:
    """Interface to a Git repository"""

    path: Path

    @staticmethod
    def clone(url: str, path: Path | str):
        """Clone a repo into the given path"""
        Repo().git("clone", url, str(path))
        return Repo(Path(path))

    def __init__(self, path: Optional[Path] = None):
        self.path = path or Path.cwd()

    @property
    def is_repo(self):
        """Get whether there is a Git repo at this location"""
        return (self.path / ".git").is_dir()

    def git(self, *args: str):
        """Run Git and echo the output"""
        with Popen(
            ["git", *args], cwd=self.path, encoding="utf-8", stdout=PIPE, stderr=STDOUT
        ) as process:
            with process.stdout:
                prefix_output(process.stdout, colorize("git: ", Color.BLUE))
            process.wait()

    def git_output(self, *args: str):
        """Run Git and return the output"""
        return subprocess.check_output(
            ["git", *args], cwd=self.path, encoding="utf-8"
        ).rstrip()

    def remote_url(self):
        """Get the URL for the main remote"""
        return self.git_output("remote", "get-url", self.git_output("remote"))

    def actions_url(self):
        """Get the GitHub actions URL, if it exists"""
        remote_url = self.remote_url()
        if remote_url.startswith("https://github.com"):
            return remote_url.removesuffix(".git") + "/actions"
        return None

    def has_changes(self):
        """Get whether there are local changes"""
        return bool(self.git_output("status", "--porcelain"))

    def fetch(self, *args: str):
        """Run 'git fetch'"""
        self.git("fetch", *args)

    def pull(self):
        """Run 'git pull'"""
        self.git("pull")

    def push(self, *args):
        """Run 'git push'"""
        self.git("push", *args)

    def get_head_ref(self):
        """Gets the symbolic ref for the head commit"""
        return self.git_output("symbolic-ref", "--short", "HEAD")

    def push_origin(self):
        """
        Pushes the current branch to origin and sets it as the upstream tracking
        branch.
        """
        self.push("-u", "origin", self.get_head_ref())

    def checkout_file(self, commit: str, path: Path):
        """
        Checks out the file at "path" from "commit".
        """
        self.git("checkout", commit, "--", str(path.relative_to(self.path)))

    def commit_changes(self, message: str):
        """
        Adds all local changes and commits them.
        """
        self.git("add", ".")
        self.git("commit", "-m", message)


def check_dependencies():
    """
    Verifies that Git is installed and required Git configuration has been set.
    """
    try:
        Repo().git_output("--version")
    except subprocess.CalledProcessError as ex:
        raise StopWizard(
            "This script requires Git. "
            "Please install it from https://git-scm.com/downloads"
        ) from ex

    _check_git_config(
        "user.name",
        "Git username not set!\nRun: git config --global user.name 'My Name'",
    )
    _check_git_config(
        "user.email",
        "Git email not set!\nRun: git config --global user.email 'example@myemail.com'",
    )


def _check_git_config(option: str, message: str):
    try:
        Repo().git_output("config", option)
    except subprocess.CalledProcessError as ex:
        raise StopWizard(message) from ex


def select_repo(config: Config) -> Repo:
    """Prompts the user to select a repo to modify"""
    if config.repo_path:
        return Repo(config.repo_path)

    repo = Repo(Path.cwd())
    if repo.is_repo and _should_use_current_directory():
        return repo

    return _clone_repo(config)


def _should_use_current_directory():
    if Path("build.yaml").exists() and Path("config/west.yml").exists():
        # Looks like a ZMK config repo. Use it automatically.
        return True

    print_block(
        f"""
        Found an existing Git repo at {Path.cwd()}
        but it doesn't look like a ZMK user config repo.
        """
    )

    edit = "Edit this repo"
    clone = "Clone a new repo here"
    cancel = "Cancel"

    response = show_menu("Select an option:", [edit, clone, cancel])

    if response == edit:
        return True

    if response == clone:
        return False

    raise StopWizard()


def _clone_repo(config):
    print_block(
        f"""
        This script must clone your user config repo locally for modifications.
        (If you have done this already, press Ctrl+C to cancel and re-run the
        script from the repo folder.)

        If you do not have a user config repo, please sign in to https://github.com,
        open the following URL, click the "Use this template" button, and follow the
        instructions to create your repo.

            {config.template_url.removesuffix(".git")}

        Next, go to your repo page on GitHub and click the "Code" button. Copy the
        repo URL and paste it here (Ctrl+Shift+V or right click).
        """
    )
    repo_url = input("Repo URL: ")

    if not repo_url:
        raise StopWizard()

    repo_name = repo_url.removesuffix(".git").split("/")[-1]

    try:
        return Repo.clone(repo_url, repo_name)
    except subprocess.CalledProcessError as ex:
        raise StopWizard(str(ex)) from ex

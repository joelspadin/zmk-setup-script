# Copyright (c) 2022 The ZMK Contributors
# SPDX-License-Identifier: MIT
"""
Simple terminal menu
"""

import shutil
from dataclasses import dataclass
from typing import Callable, Generic, Iterable, Optional, TypeVar
from . import terminal


@dataclass
class _MenuSize:
    width: int
    height: int


class StopMenu(Exception):
    """
    Exception thrown when the user cancels the menu without making a selection
    """


T = TypeVar("T")


class TerminalMenu(Generic[T]):
    """
    Manages an interactive menu in a terminal window.
    """

    title: str
    items: list[T]
    formatter: Callable[[T], str]
    focus_color: str | terminal.Color
    default_index: int
    _focus_index: int
    _scroll_index: int

    def __init__(
        self,
        title: str,
        items: Iterable[T],
        formatter: Optional[Callable[[T], str]] = None,
        focus_color: str | terminal.Color = terminal.Color.GREEN,
        default_index=0,
    ):
        self.title = title
        self.items = list(items)
        self.formatter = formatter or str
        self.focus_color = focus_color
        self.default_index = default_index
        self._focus_index = 0
        self._scroll_index = 0

    def show(self):
        """
        Displays the menu.

        :return: The selected item.
        :raises StopMenu: The user canceled the menu without making a selection.
        """
        # The cursor will be hidden on the last line of the console.
        try:
            with terminal.hide_cursor():
                self._focus_index = self.default_index

                while True:
                    menu_size = self._get_menu_size()
                    self._update_scroll_index(menu_size)

                    self._print_menu(menu_size)

                    if self._handle_input(menu_size):
                        return self.items[self._focus_index]

                    self._reset_cursor_to_top(menu_size)
        finally:
            # Add one blank line at the end to separate further output from the menu.
            print()

    def _print_menu(self, menu_size: _MenuSize):
        print(self.title)

        display_count = self._get_display_count(menu_size)

        for row in range(display_count):
            index = self._scroll_index + row
            focused = index == self._focus_index

            self._print_item(self.items[index], focused=focused, menu_size=menu_size)

    def _print_item(self, item: T, focused: bool, menu_size: _MenuSize):
        color = self.focus_color if focused else "0"
        indent = "> " if focused else "  "
        text = indent + self.formatter(item)

        # Menu items are assumed to be one line each, so truncate if needed.
        text = text[0 : menu_size.width]

        # Clear the rest of the line to hide leftover text from other menu items
        # when scrolling.
        text = text.ljust(menu_size.width)

        print(terminal.colorize(text, color))

    def _handle_input(self, menu_size: _MenuSize):
        key = terminal.read_key()

        if key == terminal.RETURN:
            return True

        if key == terminal.ESCAPE:
            raise StopMenu()

        if key == terminal.UP:
            self._focus_index -= 1
        elif key == terminal.DOWN:
            self._focus_index += 1
        elif key == terminal.PAGE_UP:
            self._focus_index -= menu_size.height
        elif key == terminal.PAGE_DOWN:
            self._focus_index += menu_size.height
        elif key == terminal.HOME:
            self._focus_index = 0
        elif key == terminal.END:
            self._focus_index = len(self.items) - 1

        self._focus_index = min(max(0, self._focus_index), len(self.items) - 1)
        return False

    def _get_menu_size(self) -> _MenuSize:
        extra_lines = 3  # console prompt + title line + empty line at end
        size = shutil.get_terminal_size()
        return _MenuSize(width=size.columns, height=size.lines - extra_lines)

    def _get_display_count(self, menu_size: _MenuSize):
        return min(len(self.items), menu_size.height)

    def _update_scroll_index(self, menu_size: _MenuSize):
        self._scroll_index = self._get_scroll_index(menu_size)

    def _get_scroll_index(self, menu_size: _MenuSize):
        items_count = len(self.items)
        display_count = self._get_display_count(menu_size)

        if items_count < display_count:
            return 0

        first_displayed = self._scroll_index
        last_displayed = first_displayed + display_count - 1

        if self._focus_index <= first_displayed:
            return max(0, self._focus_index - 1)

        if self._focus_index >= last_displayed:
            return min(items_count - 1, self._focus_index + 1) - (display_count - 1)

        return self._scroll_index

    def _reset_cursor_to_top(self, menu_size: _MenuSize):
        display_count = self._get_display_count(menu_size)

        row, _ = terminal.get_cursor_pos()
        row = max(1, row - display_count - 1)

        terminal.set_cursor_pos(row=row)


_YES = "Yes"
_NO = "No"


def show_menu(
    title: str,
    items: Iterable[T],
    formatter: Optional[Callable[[T], str]] = None,
    focus_color: str | terminal.Color = terminal.Color.GREEN,
    default_index=0,
):
    """
    Displays an interactive menu.

    :param title: Text to display at the top of the menu.
    :param items: List of items to display.
    :param formatter: Function which returns the text to display for an item.
    :param focus_color: Color of the focused menu item.
    :param default_index: Index of the item to focus initially.
    :return: The selected item.
    :raises StopMenu: The user canceled the menu without making a selection.
    """
    menu = TerminalMenu(
        title=title,
        items=items,
        formatter=formatter,
        focus_color=focus_color,
        default_index=default_index,
    )
    return menu.show()


def show_prompt(prompt: str, default_no=False):
    """
    Displays a yes/no prompt and returns whether the user selected yes
    """

    try:
        result = show_menu(prompt, [_YES, _NO], default_index=1 if default_no else 0)
        return result == _YES
    except StopMenu:
        return False

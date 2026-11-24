#!/usr/bin/env python3
"""Write a mounted disk image's Finder layout straight into its .DS_Store.

Finder's AppleScript interface is the usual way to do this, and it no longer
works: `set background picture of icon view options` returns the file it was
handed and then stores nothing — on this machine it fails the same way for an
ordinary folder on the Desktop, with Full Disk Access granted, so it is not
something a disk image can work around. Icon positions and window bounds still
take, which makes the failure quiet: you get a laid-out window with a blank
white backdrop.

So the layout is written the way dmgbuild writes it — directly, into the
volume's .DS_Store, which is the file Finder would have written anyway.

    scripts/dmg-layout.py /Volumes/TAUdo .background/background.tiff \\
        --window 600x330 --icon-size 112 \\
        --place TAUdo.app=135,150 --place Applications=335,150

Run it through uv (see scripts/release.sh) so the two small pure-Python
libraries it needs do not have to be installed globally.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias


def parse_placement(value: str) -> tuple[str, tuple[int, int]]:
    name, _, position = value.partition("=")
    x, _, y = position.partition(",")
    if not name or not x or not y:
        raise argparse.ArgumentTypeError(
            f"expected NAME=X,Y for an icon placement, got: {value}"
        )
    return name, (int(x), int(y))


def parse_size(value: str) -> tuple[int, int]:
    width, _, height = value.partition("x")
    if not width or not height:
        raise argparse.ArgumentTypeError(f"expected WIDTHxHEIGHT, got: {value}")
    return int(width), int(height)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("volume", type=Path, help="mounted volume root")
    parser.add_argument("background", help="background image, relative to the volume")
    parser.add_argument(
        "--window",
        type=parse_size,
        default=(600, 330),
        help="content size of the Finder window in points",
    )
    parser.add_argument(
        "--origin",
        type=parse_size,
        default=(120, 120),
        help="where the window opens on screen",
    )
    parser.add_argument(
        "--title-bar",
        type=int,
        default=32,
        help="height Finder adds above the content area; "
        "WindowBounds counts it, icon positions do not",
    )
    parser.add_argument("--icon-size", type=float, default=112.0)
    parser.add_argument("--text-size", type=float, default=14.0)
    parser.add_argument(
        "--place", type=parse_placement, action="append", default=[], metavar="NAME=X,Y"
    )
    arguments = parser.parse_args()

    volume: Path = arguments.volume
    background = volume / arguments.background
    if not volume.is_dir():
        print(f"error: not a mounted volume: {volume}", file=sys.stderr)
        return 1
    if not background.is_file():
        print(f"error: background image not found: {background}", file=sys.stderr)
        return 1

    width, height = arguments.window
    left, top = arguments.origin

    # An alias to the background, resolved by Finder when the image is mounted
    # somewhere else entirely. `Alias.for_file` records the volume name and the
    # path within it, which is what makes a .DS_Store written here work on the
    # reader's Mac.
    alias = Alias.for_file(str(background))

    # `bwsp` and `icvp` carry property lists; ds_store serialises them itself.
    with DSStore.open(str(volume / ".DS_Store"), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = {
            # WindowBounds measures the whole window, title bar included, while
            # the backdrop and the icon positions are laid out from the top of
            # the content area. Without this the last band of the artwork — for
            # TAUdo, the drag hint — is simply never on screen.
            "WindowBounds": f"{{{{{left}, {top}}}, {{{width}, {height + arguments.title_bar}}}}}",
            "PreviewPaneVisibility": False,
            "ShowSidebar": False,
            "ShowStatusBar": False,
            "ShowPathbar": False,
            "ShowTabView": False,
            "ShowToolbar": False,
            "SidebarWidth": 0,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 2,  # 2 = picture
            "backgroundImageAlias": alias.to_bytes(),
            "backgroundColorRed": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0,
            "iconSize": arguments.icon_size,
            "textSize": arguments.text_size,
            "gridSpacing": 100.0,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "arrangeBy": "none",
            "labelOnBottom": True,
            "showIconPreview": True,
            "showItemInfo": False,
            "scrollPositionX": 0.0,
            "scrollPositionY": 0.0,
        }

        for name, (x, y) in arguments.place:
            if not (volume / name).exists() and not (volume / name).is_symlink():
                print(f"error: nothing named {name} on {volume}", file=sys.stderr)
                return 1
            store[name]["Iloc"] = (x, y)

    os.sync()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

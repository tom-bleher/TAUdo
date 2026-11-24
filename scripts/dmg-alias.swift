#!/usr/bin/env swift
// Writes a Finder alias to /Applications with a custom icon, for the DMG window's drop slot.
// (A symlink can't carry its own icon: setting one would follow the link to /Applications.)
//   swift scripts/dmg-alias.swift <alias path> <icon png>
import AppKit

let alias = URL(fileURLWithPath: CommandLine.arguments[1])
let icon = NSImage(contentsOfFile: CommandLine.arguments[2])!
let bookmark = try URL(fileURLWithPath: "/Applications").bookmarkData(options: .suitableForBookmarkFile)
try URL.writeBookmarkData(bookmark, to: alias)
guard NSWorkspace.shared.setIcon(icon, forFile: alias.path) else { fatalError("could not set the alias icon") }

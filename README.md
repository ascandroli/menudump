# Menudump — Alfred Workflow (Swift Edition)

An Alfred Workflow that dumps the menu entries for a macOS application.

## Overview

Menudump is a Swift-based Alfred Workflow that extracts all available menu items from the frontmost application and presents them in Alfred, allowing you to quickly search and execute menu commands without using the mouse.
This is a complete rewrite of the previous project, now implemented as a single Swift script.

Menudump intentionally keeps things simple by focusing only on menu extraction. It relies on Alfred's powerful built-in capabilities for filtering or ordering, it doesn't implement its own.

If you want a feature-rich implementation of this same concept please checkout Benzi's implementation https://github.com/BenziAhamed/Menu-Bar-Search

Having said that I did add a new feature to the workflow, now you can use the keyword "cheatsheet" to display a comprehensive list of all keyboard shortcuts for the active application.

The workflow includes a hash-based caching script for compiling and running Swift files, the first run could be a bit slower but it improves execution speed on repeated runs.

## Credits

- Original ObjC implementation by ctwise
- Swift rewrite by Alejandro Scandroli

## ...
> [Check out my other workflows and my workflow design principles.](https://github.com/ascandroli/alfred-workflows)

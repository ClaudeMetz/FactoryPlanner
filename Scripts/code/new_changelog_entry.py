#!/usr/bin/env python3

# This script adds a new, blank changelog entry
# This should be run in the directory that contains your factorio installation as well as the mod project folder
# You can set a modname, although this only works if the filestructure is the same as my factoryplanner mod

import itertools
from pathlib import Path

# Script config
MODNAME = "factoryplanner"

# Update changelog file for further development
mod_path = list(itertools.islice((Path.cwd() / MODNAME).glob(MODNAME + "_*"), 1))[0]
changelog_path = mod_path / "changelog.txt"
new_changelog_entry = ("-----------------------------------------------------------------------------------------------"
                       "----\nVersion: 0.17.00\nDate: 00. 00. 0000\n  Features:\n    - \n  Changes:\n    - \n  Bugfixes:"
                       "\n    - \n\n")
with (changelog_path.open("r")) as changelog:
    old_changelog = changelog.readlines()
old_changelog.insert(0, new_changelog_entry)
with (changelog_path.open("w")) as changelog:
    changelog.writelines(old_changelog)
print("- changelog updated for further development")

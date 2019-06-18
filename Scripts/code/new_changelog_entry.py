# This script adds a new, blank changelog entry
# This should be run in the directory that contains your factorio installation as well as the mod project folder
# You can set a modname, although this only works if the filestructure is the same as my factoryplanner mod
# Takes the modname from the first command line argument

import itertools
import sys
from pathlib import Path

# Script config
MODNAME = sys.argv[1]

# Update changelog file for further development
def update_changelog():
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


if __name__ == "__main__":
    proceed = input("Sure to update the changelog dialog? (y/n): ")
    if proceed == "y":
        update_changelog()

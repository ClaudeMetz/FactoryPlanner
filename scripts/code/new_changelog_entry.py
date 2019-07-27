# This script adds a new, blank changelog entry
# It needs to be run in the same directory as the changelog that should be updated

from pathlib import Path

# Update changelog file for further development
def update_changelog():
    changelog_path = Path.cwd() / "changelog.txt"
    new_changelog_entry = ("-----------------------------------------------------------------------------------------------"
                           "----\nVersion: 0.17.00\nDate: 00. 00. 0000\n  Features:\n    - \n  Changes:\n    - \n  "
                           "Bugfixes:\n    - \n\n")
    with (changelog_path.open("r")) as changelog:
        old_changelog = changelog.readlines()
    old_changelog.insert(0, new_changelog_entry)
    with (changelog_path.open("w")) as changelog:
        changelog.writelines(old_changelog)
    print("- changelog updated for further development")


if __name__ == "__main__":
    proceed = input("Sure to update the changelog? (y/n): ")
    if proceed == "y":
        update_changelog()

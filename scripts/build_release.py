# This script will build the zipped version of the mod that is ready for release on the mod portal
# It will also first bump versions and the changelog, and commit and push the changes to Github
# This needs to run in the directory that contains your Factorio installation as well as the mod project folder
# Takes the modname from the first command line argument (although project structure needs to be as expected)
# Requires GitPython to be installed (>pip install gitpython)

import fileinput
import itertools
import json
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

import git  # gitpython module

# Script config
MODNAME = sys.argv[1]

cwd = Path.cwd()
repo = git.Repo(cwd / MODNAME)

def build_release():
    modfiles_path = cwd / MODNAME / "modfiles"
    info_json_path = modfiles_path / "info.json"
    with info_json_path.open("r") as file:
        data = json.load(file)
    split_old_mod_version = data["version"].split(".")
    split_old_mod_version[-1] = str(int(split_old_mod_version[-1]) + 1)  # update version to the new one
    new_mod_version = ".".join(split_old_mod_version)

    # Bump info.json version
    data["version"] = new_mod_version
    with info_json_path.open("w") as file:
        json.dump(data, file, indent=4)
    print("- info.json version bumped")

    # Update factorio folder mod symlink
    mods_path = cwd / "userdata" / "mods"
    old_mod_symlink = list(itertools.islice(mods_path.glob(MODNAME + "_*"), 1))[0]
    new_mod_symlink = Path(mods_path, MODNAME + "_" + new_mod_version)
    old_mod_symlink.rename(new_mod_symlink)
    print("- mod folder symlink updated")

    # Disable devmode if it is active
    tmp_path = modfiles_path / "data" / "tmp"
    init_file_path = modfiles_path / "data" / "init.lua"
    with tmp_path.open("w") as new_file, init_file_path.open("r") as old_file:
        for line in old_file:
            line = re.sub(r"^devmode = true", "--devmode = true", line)
            new_file.write(line)
    init_file_path.unlink()
    tmp_path.rename(init_file_path)
    print("- devmode disabled")

    # Update changelog file for release
    tmp_path = modfiles_path / "tmp"
    old_changelog_path = modfiles_path / "changelog.txt"
    with tmp_path.open("w") as new_file, old_changelog_path.open("r") as old_file:
        changes = 0  # Only changes the first changelog entry
        for line in old_file:
            if changes < 2 and "Version" in line:
                new_file.write("Version: " + new_mod_version + "\n")
                changes += 1
            elif changes < 2 and "Date" in line:
                new_file.write("Date: " + datetime.today().strftime("%d. %m. %Y") + "\n")
                changes += 1
            else:
                new_file.write(line)

    old_changelog_path.unlink()
    new_changelog_path = modfiles_path / "changelog.txt"
    tmp_path.rename(new_changelog_path)
    print("- changelog updated for release")

    # Create zip archive (stealthily include the LICENSE)
    tmp_license_path = modfiles_path / "LICENSE.md"
    shutil.copy(str(cwd / MODNAME / "LICENSE.md"), str(tmp_license_path))

    # Rename modfiles folder temporarily so the zip generates correctly
    full_mod_name = Path(MODNAME + "_" + new_mod_version)
    tmp_modfiles_path = cwd / MODNAME / full_mod_name
    modfiles_path.rename(tmp_modfiles_path)
    zipfile_path = Path(cwd, MODNAME, "releases", full_mod_name)
    shutil.make_archive(str(zipfile_path), "zip", str(cwd / MODNAME), str(tmp_modfiles_path.parts[-1]))
    tmp_modfiles_path.rename(modfiles_path)

    tmp_license_path.unlink()
    print("- zip archive created")

    # Commit and push to GitHub
    repo.git.add("-A")
    repo.git.commit(m="Release " + new_mod_version)
    repo.git.push("origin")
    print("- changes committed and pushed")


if __name__ == "__main__":
    proceed = input("Sure to build a release? (y/n): ")
    if proceed == "y":
        build_release()

#!/usr/bin/env python3

# This script will build the zipped version of the mod that is ready for release on the mod portal
# It will also first bump versions and the changelog, and commit and push the changes to github
# This should be run in the directory that contains your factorio installation as well as the mod project folder
# You can set a modname, although this only works if the filestructure is the same as my factoryplanner mod
# Requires GitPython to be installed (>pip install gitpython)

import fileinput
import itertools
import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import git

# Script config
MODNAME = "factoryplanner"

# Some git setup
cwd = Path.cwd()
repo = git.Repo(cwd / MODNAME)

# Determine path and version-number
mod_folder_path = list(itertools.islice((cwd / MODNAME).glob(MODNAME + "_*"), 1))[0]
old_version = mod_folder_path.parts[-1].split("_")[-1]
split_old_version = old_version.split(".")
split_old_version[-1] = str(int(split_old_version[-1]) + 1)
new_version = ".".join(split_old_version)

# Bump mod folder version
new_mod_folder_path = Path(MODNAME, MODNAME + "_" + new_version)
mod_folder_path.rename(new_mod_folder_path)
print("- mod folder version bumped")

# Update factorio folder mod symlink
factorio_mod_folder_path = list(itertools.islice(cwd.glob("Factorio_*"), 1))[0] / "mods"
old_symlink_path = list(itertools.islice(factorio_mod_folder_path.glob(MODNAME + "_*"), 1))[0]
old_symlink_path.rmdir()
new_symlink_path = Path(factorio_mod_folder_path, MODNAME + "_" + new_version)
# This kind of symlink is best done with subprocess (on Windows)
subprocess.run(["mklink", "/J", str(new_symlink_path), str(new_mod_folder_path), ">nul"], shell=True)
print("- mod folder symlink updated")

# Disable devmode if it is active
tmp_path = new_mod_folder_path / "data" / "tmp"
init_file_path = new_mod_folder_path / "data" / "init.lua"
with tmp_path.open("w") as new_file, init_file_path.open("r") as old_file:
    for line in old_file:
        line = re.sub(r"global\.devmode = true", "--global.devmode = true", line)
        new_file.write(line)
init_file_path.unlink()
tmp_path.rename(init_file_path)
print("- devmode disabled")

# Bump info.json version
info_json_path = new_mod_folder_path / "info.json"
with info_json_path.open("r") as file:
    data = json.load(file)
data["version"] = new_version
with info_json_path.open("w") as file:
    json.dump(data, file, indent=4)
print("- info.json version bumped")

# Update changelog file for release
tmp_path = new_mod_folder_path / "tmp"
old_changelog_path = new_mod_folder_path / "changelog.txt"
with tmp_path.open("w") as new_file, old_changelog_path.open("r") as old_file:
    changes = 0  # Only changes the first changelog entry
    for line in old_file:
        if changes < 2 and "Version" in line:
            new_file.write("Version: " + new_version + "\n")
            changes += 1
        elif changes < 2 and "Date" in line:
            new_file.write("Date: " + datetime.today().strftime("%d. %m. %Y") + "\n")
            changes += 1
        else:
            new_file.write(line)

old_changelog_path.unlink()
new_changelog_path = new_mod_folder_path / "changelog.txt"
tmp_path.rename(new_changelog_path)
print("- changelog updated for release")

# Create zip archive
zipfile_path = Path(cwd, MODNAME, "Releases", MODNAME + "_" + new_version)
shutil.make_archive(zipfile_path, "zip", new_mod_folder_path)
print("- zip archive created")

# Commit and push to GitHub
repo.git.add("-A")
repo.git.commit(m="Release " + new_version)
repo.git.push("origin")
print("- changes committed and pushed")

# Update workspace
workspace_path = cwd / "fp.code-workspace"
with workspace_path.open("r") as ws:
    workspace = ws.readlines()
with workspace_path.open("w") as ws:
    for line in workspace:
        ws.write(line.replace("factoryplanner_" + old_version, "factoryplanner_" + new_version))
print("- workspace updated")

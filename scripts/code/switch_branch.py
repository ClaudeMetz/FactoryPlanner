# This script will present the available branches and switch to the user-selected one, while
# assuring that the symlink in the Factorio mods folder stays compatible with the new branch
# This needs to run in the directory that contains your Factorio installation as well as the mod project folder
# Takes the modname from the first command line argument (although project structure needs to be as expected)
# Requires GitPython to be installed (>pip install gitpython)

import itertools
import json
import platform
import subprocess
import sys
from pathlib import Path

import git  # gitpython module

# Script config
MODNAME = sys.argv[1]

os = platform.system()
cwd = Path.cwd()
repo = git.Repo(cwd / MODNAME)

def switch_branch(branchname):
    # Checkout desired branch
    repo.git.checkout(branchname)
    print("- branch '" + branchname + "' checked out")

    # Determine new version number
    modfiles_path = cwd / MODNAME / "modfiles"
    with (modfiles_path / "info.json").open("r") as file:
        new_mod_version = json.load(file)["version"]

    # Update factorio folder mod symlink
    if os == "Darwin":
        mods_path = cwd / "userdata" / "mods"
        old_mod_symlink = list(itertools.islice(mods_path.glob(MODNAME + "_*"), 1))[0]
        new_mod_symlink = Path(mods_path, MODNAME + "_" + new_mod_version)
        old_mod_symlink.rename(new_mod_symlink)
    else:  # os == "Windows"
        mods_path = list(itertools.islice(cwd.glob("Factorio_*"), 1))[0] / "mods"
        old_mod_symlink = list(itertools.islice(mods_path.glob(MODNAME + "_*"), 1))[0]
        old_mod_symlink.rmdir()
        new_mod_symlink = Path(mods_path, MODNAME + "_" + new_mod_version)
        subprocess.run(["mklink", "/J", str(new_mod_symlink), str(modfiles_path), ">nul"], shell=True)
    print("- mod folder symlink updated")


if __name__ == "__main__":
    branch_map = {}
    for index, branch in enumerate(repo.branches):
        print("[" + str(index+1) + "] " + branch.name)
        branch_map[index] = branch.name

    branch_index = int(input("Select branch to switch to: ")) - 1
    if 0 <= branch_index <= (len(repo.branches) - 1):
        switch_branch(branch_map[branch_index])

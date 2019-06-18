# This script checks out the given git branch and adjusts the workspace and mod folder symlink.
# This is necessary because two branches can have different release versions of the mod
# which in turn have different folder names.
# Requires GitPython to be installed (>pip install gitpython)
# Takes the modname from the first command line argument

import itertools
import subprocess
import sys
from pathlib import Path

import git

# Script config
MODNAME = sys.argv[1]

def checkout_branch(branchname):
    # Some git setup
    cwd = Path.cwd()
    repo = git.Repo(cwd / MODNAME)

    # Determine old version number
    mod_folder_path = list(itertools.islice((cwd / MODNAME).glob(MODNAME + "_*"), 1))[0]
    old_version = mod_folder_path.parts[-1].split("_")[-1]
    
    # Checkout desired branch
    repo.git.checkout(branchname)
    print("- branch " + branchname + " checked out")

    # Determine new version number
    mod_folder_path = list(itertools.islice((cwd / MODNAME).glob(MODNAME + "_*"), 1))[0]
    new_version = mod_folder_path.parts[-1].split("_")[-1]

    # Update factorio folder mod symlink
    factorio_mod_folder_path = list(itertools.islice(cwd.glob("Factorio_*"), 1))[0] / "mods"
    old_symlink_path = list(itertools.islice(factorio_mod_folder_path.glob(MODNAME + "_*"), 1))[0]
    old_symlink_path.rmdir()
    new_mod_folder_path = (cwd / MODNAME / (MODNAME + "_" + new_version))
    new_symlink_path = Path(factorio_mod_folder_path, MODNAME + "_" + new_version)
    # This kind of symlink is best done with subprocess (on Windows)
    subprocess.run(["mklink", "/J", str(new_symlink_path), str(new_mod_folder_path), ">nul"], shell=True)
    print("- mod folder symlink updated")

    # Update workspace
    workspace_path = cwd / (MODNAME + ".code-workspace")
    with workspace_path.open("r") as ws:
        workspace = ws.readlines()
    with workspace_path.open("w") as ws:
        for line in workspace:
            ws.write(line.replace(MODNAME + "_" + old_version, MODNAME + "_" + new_version))
    print("- workspace updated")

    
if __name__ == "__main__":
    branchname = input("Which branch to checkout?: ")
    if branchname != "":
        checkout_branch(branchname)

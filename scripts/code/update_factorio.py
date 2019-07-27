# This script will update the version of factorio that is currently installed
# It will also carry over settings, mods and saves, update the log- and run-files, and re-symlink the mod folder
# This needs to run in the directory that contains the old version of factorio, the new zipped one and the mod project folder
# Takes the modname from the first command line argument (although project structure needs to be as expected)

import itertools
import json
import shutil
import subprocess
import sys
from pathlib import Path

# Script config
MODNAME = sys.argv[1]
SETTINGS = """; version=5
[other]
autosave-interval=0
check-updates=false
[sound]
music-volume=0.000000
wind-volume=0.000000
[interface]
show-tips-and-tricks=false
[graphics]
cache-sprite-atlas=true
compress-sprite-atlas-cache=true
graphics-quality=normal
show-clouds=false"""

def update_factorio():
    # Determine paths and versions
    cwd = Path.cwd()
    old_factorio_path = list(itertools.islice(cwd.glob("Factorio_*"), 1))[0]
    zip_file_path = list(itertools.islice(cwd.glob("Factorio_*.zip"), 1))[0]
    new_factorio_version = zip_file_path.parts[-1].split("_")[-1][:-4]
    modfiles_path = (cwd / MODNAME / "modfiles")
    info_json_path = modfiles_path / "info.json"
    with info_json_path.open("r") as file:
        mod_version = json.load(file)["version"]

    # Extract zip file
    shutil.unpack_archive(zip_file_path, cwd, "zip")
    new_factorio_path = Path(cwd / ("Factorio_" + new_factorio_version))
    zip_file_path.unlink()
    print("- ZIP file extracted")

    # Update settings
    config_path = new_factorio_path / "config"
    config_path.mkdir()
    with ((config_path / "config.ini").open("w")) as config_file:
        config_file.write(SETTINGS)
    print("- settings updated")

    # Replace symlinks
    factorio_exe_path = new_factorio_path / "bin" / "x64" / "factorio.exe"
    symlink_path = cwd / "Factorio"
    symlink_path.unlink()
    subprocess.run(["mklink", str(symlink_path), str(factorio_exe_path), ">nul"], shell=True)
    print("- factorio.exe link created"),

    factorio_log_path = new_factorio_path / "factorio-current.log"
    symlink_path = cwd / "current-log"
    symlink_path.unlink()
    subprocess.run(["mklink", str(symlink_path), str(factorio_log_path), ">nul"], shell=True)
    print("- current-log link created")

    new_mods_path = new_factorio_path / "mods"
    new_mods_path.mkdir()
    symlink_path = new_mods_path / (MODNAME + "_" + mod_version)
    subprocess.run(["mklink", "/J", str(symlink_path), str(modfiles_path), ">nul"], shell=True)
    print("- mod symlink created")

    # Copy over other mods
    old_mods_path = old_factorio_path / "mods"
    shutil.copy(str(old_mods_path / "mod-list.json"), str(new_mods_path / "mod-list.json"))
    for mod in old_mods_path.glob("*.zip"):
        shutil.copy(str(mod), str(new_mods_path / mod.parts[-1]))
    print("- other mods moved over")

    # Copy over saves
    old_saves_path = old_factorio_path / "saves"
    new_saves_path = new_factorio_path  / "saves"
    new_saves_path.mkdir()
    for save in old_saves_path.glob("*.zip"):
        shutil.copy(str(save), str(new_saves_path / save.parts[-1]))
    print("- saves moved over")

    # Remove old version
    (old_mods_path / (MODNAME + "_" + mod_version)).rmdir()
    shutil.rmtree(old_factorio_path)
    print("- old version removed")


if __name__ == "__main__":
    proceed = input("Sure to update Factorio? (y/n): ")
    if proceed == "y":
        update_factorio()

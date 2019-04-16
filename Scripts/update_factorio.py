#!/usr/bin/env python3

# This script will update the version of factorio that is currently installed
# It will also carry over settings, update the log- and run-files, and re-symlink the mod folder
# This should be run in the directory that contains the old version of factorio, as well as the new, zipped one
# You can set a modname, although this only works if the filestructure is the same as my factoryplanner mod

from pathlib import Path
import itertools
import subprocess
import shutil

# Script config
MODNAME = "factoryplanner"
SETTINGS = """; version=5
[other]
autosave-interval=0
check-updates=false
[sound]
music-volume=0.000000
[interface]
show-tips-and-tricks=false
[graphics]
cache-sprite-atlas=true
graphics-quality=normal
show-clouds=false"""

# Determine paths and versions
cwd = Path.cwd()
old_factorio_path = list(itertools.islice(cwd.glob("Factorio_*"), 1))[0]
old_factorio_version = old_factorio_path.parts[-1].split("_")[-1]
zip_file_path = list(itertools.islice(cwd.glob("Factorio_*.zip"), 1))[0]
new_factorio_version = zip_file_path.parts[-1].split("_")[-1][:-4]
mod_path = list(itertools.islice((cwd / MODNAME).glob(MODNAME + "_*"), 1))[0]
mod_version = mod_path.parts[-1].split("_")[-1]

# Extract zip file
shutil.unpack_archive(zip_file_path, cwd, "zip")
new_factorio_path = Path(cwd / ("Factorio_" + new_factorio_version))
zip_file_path.unlink()
print("- ZIP file extracted")

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

factorio_mod_path = new_factorio_path / "mods"
factorio_mod_path.mkdir()
symlink_path = factorio_mod_path / (MODNAME + "_" + mod_version)
subprocess.run(["mklink", "/J", str(symlink_path), str(mod_path), ">nul"], shell=True)
print("- mod symlink created")

# Update settings
config_path = new_factorio_path / "config"
config_path.mkdir()
with ((config_path / "config.ini").open("w")) as config_file:
    config_file.write(SETTINGS)
print("- settings updated")

# Remove old version
(old_factorio_path / "mods" / (MODNAME + "_" + mod_version)).rmdir()
shutil.rmtree(old_factorio_path)
print("- old version removed")

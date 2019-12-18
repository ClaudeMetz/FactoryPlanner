# This script adds a new, blank migration and integrates it properly
# It needs to be run in the root of the folder that contains the mod files
# Folder structure needs to be the same as Factory Planner to work

import json
import shutil
import re
from pathlib import Path

cwd = Path.cwd()

def new_migration():
    # Determine the next mod version
    with (cwd / "info.json").open("r") as file:
        split_old_mod_version = json.load(file)["version"].split(".")
    split_old_mod_version[-1] = str(int(split_old_mod_version[-1]) + 1)  # update version to the new one
    new_mod_version = "_".join(split_old_mod_version)

    # Add a new migration file, targeted at the next version, using the blank 0_0_0 template
    migrations_path = cwd / "data" / "migrations"
    blank_migration_path = (migrations_path / "migration_0_0_0.lua")
    new_migration_path = (migrations_path / "migration_{}.lua".format(new_mod_version))
    shutil.copy(blank_migration_path, new_migration_path)

    # Update the new file to the desired version
    tmp_path = cwd / "tmp"
    with tmp_path.open("w") as new_file, new_migration_path.open("r") as old_file:
        for line in old_file:
            line = re.sub("0_0_0", new_mod_version, line)
            new_file.write(line)
    new_migration_path.unlink()
    tmp_path.rename(new_migration_path)
    print("- migration file created")

    # Load and update the masterlist
    masterlist_path = migrations_path / "masterlist.json"
    with masterlist_path.open("r") as file:
        masterlist = json.load(file)
    masterlist.append(new_mod_version.replace("_", "."))
    with masterlist_path.open("w") as file:
        json.dump(masterlist, file, indent=4)
    print("- masterlist updated")

    # Update migrator to include the new migration (a bit janky)
    migrator_path = cwd / "data" / "handlers" / "migrator.lua"
    with (migrator_path.open("r")) as migrator:
        migrator_lines = migrator.readlines()

    # Remove all require lines and add the updated ones according to the masterlist
    migrator_lines[:] = [line for line in migrator_lines if not "require" in line]
    for version in reversed(masterlist):
        formatted_version = version.replace(".", "_")
        migrator_lines.insert(0, "require(\"data.migrations.migration_{}\")\n".format(formatted_version))

    # Update the migrator-masterlist in the same way
    version_line_regex = r"^\s+\[\d+\] = {version=.+},?\n$"
    migrator_lines[:] = [line for line in migrator_lines if not re.fullmatch(version_line_regex, line)]
    for line_index, line in enumerate(migrator_lines):
        if "migration_masterlist = {" in line:
            version_index = 1
            for version in masterlist:
                new_version_line = "    [{0}] = {{version=\"{1}\"}},\n".format(version_index, version)
                migrator_lines.insert(line_index+version_index, new_version_line)
                version_index += 1
            break

    with (migrator_path.open("w")) as migrator:
        migrator.writelines(migrator_lines)
    print("- migrator file updated")


if __name__ == "__main__":
    proceed = input("Sure to add a new migration? (y/n): ")
    if proceed == "y":
        new_migration()

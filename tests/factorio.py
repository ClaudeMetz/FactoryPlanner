#!/usr/bin/env python3
"""Launch Factorio with a writable data directory belonging to this worktree."""

import os
from functools import cached_property
from pathlib import Path
import re
import shutil
import subprocess
import sys


def workspace():
    return Path(os.environ.get("GITHUB_WORKSPACE", Path(__file__).resolve().parent.parent)).resolve()


def executable():
    requested = os.environ.get("FACTORIO")
    if requested:
        requested = os.path.expanduser(requested)
        found = shutil.which(requested)
        if found:
            return Path(found).resolve()
        raise RuntimeError(f"Factorio executable not found: {requested}")

    found = shutil.which("factorio")
    if found:
        return Path(found).resolve()
    defaults = {
        "darwin": "/Applications/factorio.app/Contents/MacOS/factorio",
        "linux": "/opt/factorio/bin/x64/factorio",
    }
    default = defaults.get(sys.platform)
    if default and Path(default).is_file():
        return Path(default)
    raise RuntimeError("Set FACTORIO to the game executable, or put it on PATH")


def user_data():
    if os.environ.get("FACTORIO_USERDATA"):
        return Path(os.environ["FACTORIO_USERDATA"]).expanduser()
    if sys.platform == "win32":
        return Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / "Factorio"
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/factorio"
    return Path.home() / ".factorio"


def config_text(original, instance, read_data):
    # Preserve personal settings and root-level config-version while isolating all writes
    section = re.search(r"(?ms)^\[path\][^\n]*\n(.*?)(?=^\[|\Z)", original)
    body = section[1] if section else ""
    write_data = f"write-data={instance.as_posix()}"
    if re.search(r"(?m)^[ \t]*write-data[ \t]*=", body):
        body = re.sub(r"(?m)^[ \t]*write-data[ \t]*=.*$", lambda _: write_data, body)
    else:
        body = body.rstrip() + "\n" + write_data + "\n"
    body = body.rstrip("\n") + "\n"
    if not re.search(r"(?m)^[ \t]*read-data[ \t]*=", body):
        body += f"read-data={read_data}\n"
    if section:
        return original[:section.start(1)] + body + original[section.end(1):]
    return original.rstrip() + "\n[path]\n" + body.lstrip("\n")


class Factorio:
    def __init__(self, root):
        self.root = root
        self.instances = Path(self.git("rev-parse", "--path-format=absolute", "--git-common-dir").strip()) / "factorio-instances"
        self.instance = self.instances / Path(self.git("rev-parse", "--show-toplevel").strip()).name

    @cached_property
    def executable(self):
        return executable()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args],
                                       text=True, encoding="utf-8")

    def prepare(self, *, test_directory=None):
        # NUL-separated records preserve Windows separators, spaces and non-ASCII paths
        worktrees = {Path(entry.removeprefix("worktree ")).name
                     for entry in self.git("worktree", "list", "--porcelain", "-z").split("\0")
                     if entry.startswith("worktree ")}
        if self.instances.exists():
            for directory in self.instances.iterdir():
                if directory.is_dir() and directory.name not in worktrees:
                    shutil.rmtree(directory)

        instance = test_directory if test_directory is not None else self.instance
        self.config = instance / "config/config.ini"
        self.config.parent.mkdir(parents=True, exist_ok=True)
        # Packaged macOS uses Contents/data; Linux and Windows use data beside bin
        candidates = [self.executable.parent.parent / "data",
                      self.executable.parent.parent.parent / "data"]
        read_data = next((path.as_posix() for path in candidates if path.is_dir()),
                         "__PATH__system-read-data__")
        if test_directory is not None:
            # A fresh test directory excludes settings and player data from earlier launches
            contents = f"[path]\nread-data={read_data}\nwrite-data={instance.as_posix()}\n"
        else:
            userdata = user_data()
            player_data = userdata / "player-data.json"
            if player_data.is_file():
                shutil.copyfile(player_data, instance / "player-data.json")
            source_config = userdata / "config/config.ini"
            original = source_config.read_text(encoding="utf-8-sig") if source_config.is_file() else ""
            contents = config_text(original, instance, read_data)
        self.config.write_text(contents, encoding="utf-8")

    def command(self, args):
        return [str(self.executable), "-c", str(self.config), *map(str, args)]


def main():
    try:
        game = Factorio(workspace())
        if sys.argv[1:] == ["--instance"]:
            print(game.instance)
            return 0
        game.prepare()
        return subprocess.run(game.command(sys.argv[1:]), stderr=subprocess.STDOUT).returncode
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())

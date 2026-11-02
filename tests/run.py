#!/usr/bin/env python3
"""Run FactoryPlanner tests on Windows, Linux or macOS using the Python standard library."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from factorio import Factorio, workspace


def enable_colors():
    if not sys.stdout.isatty() or "NO_COLOR" in os.environ or os.environ.get("TERM") == "dumb":
        return False
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        import msvcrt

        console = ctypes.windll.kernel32
        handle = wintypes.HANDLE(msvcrt.get_osfhandle(sys.stdout.fileno()))
        mode = wintypes.DWORD()
        # Enable processed output and virtual terminal sequences, preserving other flags
        return bool(console.GetConsoleMode(handle, ctypes.byref(mode))
                    and console.SetConsoleMode(handle, mode.value | 0x0005))
    return True


COLORS = enable_colors()


def styled(text, code):
    return f"\033[{code}m{text}\033[0m" if COLORS else text


def lua_string(value):
    # JSON's Unicode escapes aren't Lua strings; escape control bytes as decimal instead
    escaped = []
    for char in value:
        if char in ('"', "\\"):
            escaped.append("\\" + char)
        elif ord(char) < 32 or ord(char) == 127:
            escaped.append(f"\\{ord(char):03d}")
        else:
            escaped.append(char)
    return '"' + "".join(escaped) + '"'


def report_lines(log):
    lines, reporting = [], False
    for line in log.splitlines():
        if line.endswith("FPTEST_REPORT"):
            reporting = True
        elif line.endswith("FPTEST_REPORT_END"):
            reporting = False
        elif reporting:
            lines.append(line)
    return lines


def count_label(count, noun):
    return f"{count} {noun}{'' if count == 1 else 's'}"


class Runner:
    def __init__(self, root, temporary, timeout):
        self.root = root
        self.temporary = temporary
        self.timeout = timeout
        self.game = Factorio(root)
        self.game.prepare(test_directory=temporary / "instance")
        self.failure_dir = None
        self.mods = temporary / "mods"

    def run_configuration(self, suite, configuration, case_filter):
        selected = lua_string(configuration) if configuration else "nil"
        options = f"return {{configuration={selected}, filter={lua_string(case_filter)}}}\n"
        (self.mods / "factoryplanner-test/options.lua").write_text(options, encoding="utf-8")
        name = f"{suite}-{configuration or 'first'}"
        command = self.game.command(["--mod-directory", self.mods,
                                     "--test-scenario", "factoryplanner-test/tests"])
        logfile = self.temporary / "run.log"
        with logfile.open("w", encoding="utf-8") as output:
            try:
                exit_code = subprocess.run(command, timeout=self.timeout,
                                           stdout=output, stderr=subprocess.STDOUT).returncode
            except subprocess.TimeoutExpired:
                exit_code = 124
        log = logfile.read_text(encoding="utf-8", errors="replace")
        report = report_lines(log)
        for line in report:
            print(line.replace("✓", styled("✓", "32")).replace("✗", styled("✗", "31")))
        if exit_code:
            reason = (f"game timed out after {self.timeout} seconds" if exit_code == 124
                      else f"game failed (exit {exit_code})")
            print(f"  {styled('✗', '31')} {reason} [{name}]")
            if exit_code == 124 or not any("✗" in line for line in report):
                for line in log.splitlines()[-20:]:
                    print(f"    | {line}")
            if self.failure_dir is None:
                self.failure_dir = Path(tempfile.mkdtemp(prefix="factoryplanner-test-failures-"))
            destination = self.failure_dir / f"{name}.log"
            shutil.copyfile(logfile, destination)
            print(f"    Log: {destination}")
        # These markers supply presentation and discovery only; Factorio owns the verdict
        configurations = re.findall(r"FPTEST_CONFIGURATION ([a-zA-Z0-9_-]+)$", log, re.MULTILINE)
        counts = re.findall(r"FPTEST_PASSED ([0-9]+)$", log, re.MULTILINE)
        return exit_code == 0, int(counts[-1]) if counts else 0, configurations

    def prepare_suite(self, suite):
        if self.mods.exists():
            shutil.rmtree(self.mods)
        shutil.copytree(self.root / "modfiles", self.mods / "factoryplanner")
        shutil.copytree(self.root / "tests/mod", self.mods / "factoryplanner-test")
        shutil.copytree(self.root / "tests/suites" / suite, self.mods / "factoryplanner-test/suite")
        enabled = ("base", "recycler", "factoryplanner", "factoryplanner-test")
        disabled = ("space-age", "quality", "elevated-rails")
        mods = [{"name": name, "enabled": name in enabled} for name in (*enabled, *disabled)]
        (self.mods / "mod-list.json").write_text(json.dumps({"mods": mods}), encoding="utf-8")

    def run_suite(self, suite, configuration="", case_filter=""):
        print(styled(suite, "1"), flush=True)
        self.prepare_suite(suite)
        ok, passed, configurations = self.run_configuration(suite, configuration, case_filter)
        failed, count = int(not ok), 1
        if not configuration:
            for selected in configurations[1:]:
                ok, cases, _ = self.run_configuration(suite, selected, case_filter)
                passed += cases
                failed += int(not ok)
                count += 1
        summary = f"{passed} passed · {count_label(count, 'configuration')}"
        if failed:
            summary += f" · {count_label(failed, 'configuration')} failed"
        print(f"  {summary}", flush=True)
        return failed == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command")
    commands.add_parser("suites", help="Run all suites and configurations (default)")
    suite_parser = commands.add_parser("suite", help="Run one suite")
    suite_parser.add_argument("name")
    suite_parser.add_argument("configuration", nargs="?", default="")
    suite_parser.add_argument("case_filter", nargs="?", default="", help="Lua pattern matched against case names")
    args = parser.parse_args()
    root = workspace()
    if args.command == "suite":
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]*", args.name) or not (root / "tests/suites" / args.name / "suite.lua").is_file():
            parser.error(f"Unknown suite: {args.name}")
        if args.configuration and not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]*", args.configuration):
            parser.error(f"Invalid configuration name: {args.configuration}")
    timeout = os.environ.get("FACTORIO_TEST_TIMEOUT", "30")
    if not re.fullmatch(r"[1-9][0-9]*", timeout):
        parser.error("FACTORIO_TEST_TIMEOUT must be a positive number of seconds")

    try:
        with tempfile.TemporaryDirectory(prefix="factoryplanner-tests-") as temporary:
            runner = Runner(root, Path(temporary), int(timeout))
            help_result = subprocess.run([str(runner.game.executable), "--help"],
                                         timeout=int(timeout), stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
            if help_result.returncode or "--test-scenario" not in help_result.stdout:
                raise RuntimeError("Tests require Factorio with --test-scenario support (2.1.24 or newer)")
            if args.command == "suite":
                return 0 if runner.run_suite(args.name, args.configuration, args.case_filter) else 1
            suites = sorted(path.parent.name for path in (root / "tests/suites").glob("*/suite.lua"))
            if not suites:
                raise RuntimeError("No suites found")
            failed = [suite for suite in suites if not runner.run_suite(suite)]
            if failed:
                print(styled("Failed suites: " + " ".join(failed), "31"))
                return 1
            print(styled("All suites passed", "32"))
            return 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())

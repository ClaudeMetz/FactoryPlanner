# Tests

The launcher runs natively on Windows, Linux and macOS. It requires Python 3.10+
(with no extra packages), Git on PATH, and Factorio 2.1.24 or newer with
`--test-scenario` support. Bash and `timeout` are not needed to run tests.

Run commands from the repository root. On Linux and macOS:

```sh
python3 tests/run.py                                  # All suites and configurations
python3 tests/run.py suite gui                        # One suite
python3 tests/run.py suite gui no-wagons               # One prototype configuration
python3 tests/run.py suite data normal Clipboard      # Filter case names with a Lua pattern
python3 tests/run.py suite solver input-targets InputPacing_simplex
```

On Windows, use `py -3` in place of `python3`, from PowerShell or Command Prompt:

```powershell
$env:FACTORIO = 'C:\Program Files\Factorio\bin\x64\factorio.exe'
py -3 tests/run.py
```

The explicit `suites` command also runs all suites and configurations.

In Command Prompt, set the executable with
`set "FACTORIO=C:\Program Files\Factorio\bin\x64\factorio.exe"` instead.

The launcher uses `FACTORIO` when set, then looks for `factorio` on PATH. Otherwise
it tries `/Applications/factorio.app/Contents/MacOS/factorio` on macOS or
`/opt/factorio/bin/x64/factorio` on Linux. For a Steam installation, another install
location, or Windows without Factorio on PATH, set `FACTORIO` to the actual executable.
On Linux and macOS, for example:

```sh
export FACTORIO="/path/to/factorio/bin/x64/factorio"
```

Test commands use the installed executable without updating it. CI provisions the
newest available Python 3.13 build compatible with the runner before testing, and runs
`bash tests/update-factorio.sh` as a separate step before testing. You can also run
it manually for a Linux headless installation; update checks and downloads are
best effort, so a failed update does not prevent testing the installed version.
The Ubuntu 20.04 runner currently resolves to Python 3.13.3; newer builds from
`setup-python` require upgrading the runner OS.

## Organization

| Suite | Coverage |
| --- | --- |
| `lib` | Formatting, expressions, defaults and utility behavior |
| `data` | Object definitions, current-format packing/cloning, clipboard semantics and model calculations |
| `generator` | Prototype interpretation and generated objects |
| `solver` | Assignments, rates, consumption and nested-floor calculations |
| `gui` | Item views, pickers, menus, districts, shortcuts and tooltips |

Tests do not cover migrations. Packing/unpacking and cloning checks use objects
created by the current code. Do not add legacy-save fixtures, migration calls, or
export/import round trips that invoke migrations. Each configuration starts a fresh
scenario, so ordinary tests do not load an older save or trigger configuration changes.

A case should cover one behavior. Keep meaningful transitions such as disabling
and re-enabling a target together; split unrelated scenarios into separate named
cases. Parameterized cases include their solver or definition type in their name,
so each combination is reported and can be filtered independently.

GUI cases may use the real solver to verify an interaction. Arithmetic expectations
belong in solver cases; prototype expectations belong in generator cases. A GUI
assertion verifies API state, not rendered appearance or physical input handling.

## Prototype configurations

Each directory in `tests/suites/` has a `suite.lua` manifest. It returns an ordered
array of configurations with an explicit list of data-stage setup functions:

```lua
local cases = require("suite.input-targets")

return {{
    name = "input-targets",
    setup = {require("prototypes").input_targets},
    cases = cases
}}
```

The launcher prepares mod copies once per suite and rewrites `options.lua` for each
configuration. Every configuration gets a fresh Factorio launch using the test mod's
minimal scenario. All setup functions run once, in order, regardless of the runtime
case filter. Filtering a case therefore keeps its prototype environment identical to
the complete run. A setup failure stops that configuration before runtime checks.

Use separate configurations when fixtures change global prototype properties or
interact through generated recipes. Share compatible setup explicitly. Prototype
fixtures needed by multiple suites live in `tests/mod/prototypes.lua`; a fixture used
only by one module can keep its `setup` function beside its checks, referenced by
the configuration. The runner does not discover setup through selected cases.

Configurations use letters, digits, hyphens and underscores. The first configuration
reports the manifest to the launcher, avoiding a separate discovery launch or Lua
interpreter. Later configurations and suites still run after a failure.

The launcher writes `options.lua` for configuration and case selection. Configuration
setup needs these options during the data stage, where `script.test_arg` is unavailable.

## Runtime fixtures and assertions

Each case supplies `check(context)`. Cases run in name order with isolated player
preferences, UI state, navigation context, clipboard and realm. The fixture scope
removes newly created model objects and factory inventories, GUI roots and scheduled
callbacks, and restores the cursor, opened GUI and pause state even when setup or checks fail.
This is not a snapshot of all game state: prototypes are shared for the configuration,
and changes outside the owned player state require explicit cleanup.

Shared fixture builders live in `tests/mod/fixtures.lua`; assertions and GUI helpers
live in `tests/mod/helpers.lua`. Related behaviors share test files while retaining
independent case names:

- `fixtures.factory`, `fixtures.line` and `fixtures.target` arrange ordinary objects.
- `fixtures.view(context)` prepares item-view preferences and returns the player and state.
- `context.player` is the test player; `context.classes` supplies the model classes.
- `context.set(object, key, value)` restores an external property after the case.
- `context.defer(function() ... end)` registers other cleanup in reverse order.
- `helpers.gui.require(root, tags)` requires a unique matching element; `helpers.gui.find` permits absence.
- `helpers.gui.click` and `helpers.gui.dispatch` supply consistent event fields and accept overrides.
- `helpers.collector()` collects independent comparisons through `check`, `equal`
  and `close`, then reports them with `done()`.

Use ordinary `assert` for prerequisites and dependent interactions. Include a useful
message; numeric comparisons should include expected and actual values. Preserve
simple, hand-computable expected results instead of deriving them from the behavior
being tested. Fixture cleanup failure stops the remaining cases in that configuration.

## Reports and CI

Output lists individual tests under each suite and includes configuration names when
needed. Failures include tracebacks. A filter matching no cases is a failure.
Temporary mod copies and successful logs are removed; failed logs are retained at the
printed path. Each test invocation prepares a fresh temporary instance and a minimal
config once, then reuses them for its game launches. Tests use the installation's
data and standard settings, without copying personal configuration or player data.
The instance is removed when the invocation ends.

The standalone development launcher, `tests/factorio.py`, keeps a persistent instance
per worktree under the shared Git directory's `factorio-instances/`. It copies user
settings from `%APPDATA%/Factorio` on Windows, `~/Library/Application Support/factorio`
on macOS, or `~/.factorio` on Linux. Set `FACTORIO_USERDATA` to override that location
for development launches. `player-data.json` is copied only when present, and a
minimal config is generated if no personal config exists.

`python3 tests/factorio.py --instance` prints the development instance path, and
`python3 tests/factorio.py --dump-data` runs Factorio in it. Use `py -3` on Windows.

Factorio's `--test-scenario` mode creates a player in headless mode. The runner is an
ordinary `on_tick` listener inside FactoryPlanner's Lua context. On the first tick,
it checks that player initialization completed, runs the cases, and reports results.
Calling `script.finish_test` ends the process after that tick, so no temporary event
handler or unregistration is needed. Factorio's exit status determines success or
failure, including empty selections and setup errors. Log markers supply reports,
passed-case totals, and configuration discovery; they do not determine the verdict.

Each game process has a 30-second timeout, including startup. Override it with
`FACTORIO_TEST_TIMEOUT` in seconds. Python kills a timed-out process and waits for
it to exit; there is no additional grace period. A timeout fails the run. The launcher
does not use `--test-ticks`, which would exit successfully without requiring test completion.

CI runs each suite as a job. Add new suite names to `.github/workflows/ci.yml` and the
VS Code task picker; additional configurations require no CI changes.

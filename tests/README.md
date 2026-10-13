# Tests

Run commands from the repository root. Set `FACTORIO` to the game executable if it
isn't installed at `/opt/factorio/bin/x64/factorio`. On macOS:

```sh
export FACTORIO=/Applications/factorio.app/Contents/MacOS/factorio
```

```sh
bash tests/run.sh save-create                   # Smoke test map creation
bash tests/run.sh suites                        # All suites and configurations
bash tests/run.sh suite views                   # One suite
bash tests/run.sh suite views no-wagons          # One configuration
bash tests/run.sh suite lib normal Clipboard    # Filter case names with a Lua pattern
```

Each directory in `tests/suites/` contains a `suite.lua` manifest and its test
modules. The manifest returns an ordered array of named configurations:

```lua
local wagons = require("suite.wagons")

return {
    {name="normal", cases={testWagonViews=wagons.case(true, true)}},
    {name="no-wagons", cases={testWagonViews=wagons.case(false, false)}}
}
```

Every configuration gets a fresh Factorio launch using the same clean save.
Cases within it share the game's prototypes and runtime state. A case can supply
`setup()` for data-stage prototype changes and must supply `check(context)` for
runtime assertions. Cases run in name order; runtime checks should restore state
they modify. A setup failure stops that configuration before its runtime checks.

Keep compatible cases in one configuration. Add configurations when tests need
different prototypes, such as missing wagons. Single-configuration suites use the
same structure. Configuration names use letters, digits, hyphens, and underscores.

The first configuration reports the manifest to the launcher while it runs, so
suite discovery needs neither a separate game launch nor a standalone Lua
interpreter. A failure still allows the remaining configurations and suites to run
once their manifest has loaded.

Output lists individual tests directly under each suite, followed by a suite total.
Suites with multiple configurations append the configuration name to each test to
distinguish repeated cases. Failures include tracebacks. A filter matching no cases
is a failure.

Temporary mod copies and successful logs are removed after each invocation. Failed
logs are retained in a temporary directory whose path is printed with the failure.
The shared `tests/factorio.sh` wrapper also maintains one game instance per worktree.

CI runs each suite as a job. When adding a suite, add its name to the matrix in
`.github/workflows/ci.yml`; additional configurations need no CI changes.

# Compatibility Interface Docs

Factory Planner offers certain ways to influence its functionality from the outside, as a way to provide improved compatibility with mods making use of custom scripting. This lists and explains these interfaces.

Note that this compatibility interface is currently very limited, but I'm open to expanding it to fit your use case. Just open a Github issue presenting it and we'll go from there.

## Index

- [Runtime integrations](#runtime-integrations)
  - [`invalidate`](#invalidate)
- [Static integrations](#static-integrations)
  - [`recycling_recipes`](#recycling_recipes)
  - [`compacting_recipes`](#compacting_recipes)
  - [`machine_effects`](#machine_effects)
  - [`overwrite_recipe_picker`](#overwrite_recipe_picker)
  - [`recipe_substitutions`](#recipe_substitutions)

## Runtime integrations

A runtime integration can be used at any time in the [lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html). It influences Factory Planner from that point on. It's implemented via a [remote interface](https://lua-api.factorio.com/latest/classes/LuaRemote.html) called `"fp-integration"` that mods can call. Details on how to use the individual integrations can be found in dedicated sections below.

All runtime integrations require a `version` integer to be included to indicate the format used. The individual integration docs below indicate which version they describe. They also indicate the first release of Factory Planner that the interface became available on.

### `invalidate`

**Current version:** `1`, available from `2.1.11`

Some static integrations are collected per-force, which means Factory Planner needs to know when a mod's per-force state changed. There's no way for it to notice this on its own, so mods managing such state by scripting are required to call this. It carries no data itself, it only prompts Factory Planner to read that static integration again.

The integration expects the name of the `integration` that went stale. Only one can be named at a time, so a mod that changed several of them calls this once for each.

This does not need to be repeated after [on_configuration_changed](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html#on_configuration_changed), because Factory Planner re-reads all per-force integrations at that point regardless.

#### Example

```lua
remote.call("fp-integration", "invalidate", {
    version = 1,
    integration = "machine_effects"
})
```

## Static integrations

A static integration needs to be set up as a [remote interface](https://lua-api.factorio.com/latest/classes/LuaRemote.html) inside the mod that wishes to use it. Factory Planner will then call this interface at specific times to retrieve the integration data. To that end, the interface needs to return a specific format, described for each integration in dedicated sections below.

For Factory Planner to be able to find the remote interface, it needs to follow a specific naming convention: It needs to start with `"fp-integration-"`, followed by the exact internal name of the mod. This is the one called `"name"` in the `info.json` file. The examples below mimmic a mod called `"example-mod"`, thus add an interface called `"fp-integration-example-mod"`.

All static integrations require a `version` integer to be included to indicate the format used. The individual integration docs below indicate which version they describe. They also indicate the first release of Factory Planner that the interface became available on.

Note that mods need to set up their remote interface during the `control.lua` stage of the [lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html), so Factory Planner has access to it at any point it needs to. In addition, if more than one static integration is used, they need to be bundled into the same `remote.add_interface` call.

### `recycling_recipes`

**Current version:** `1`, available from `2.1.3`

This integration allows mods to indicate recycling recipes to Factory Planner. It uses this information to offer users a toggle to ignore these recipes in the picker, as they can clutter up the choices for many recipes. Recycling recipes don't have a strict definition, but they are generally understood to reverse another crafting process.

The integration expects a table called `recipes`, which contains a list of names that should be marked as recycling recipes.

#### Example

```lua
remote.add_interface("fp-integration-example-mod", {
    recycling_recipes = (function()
        return {
            version = 1,
            recipes = {"landfill"}
        }
    end)
})
```

### `compacting_recipes`

**Current version:** `1`, available from `2.1.3`

This integration allows mods to indicate compacting recipes to Factory Planner. It uses this information to offer users a toggle to ignore these recipes in the picker, as they can clutter up the choices for many recipes. Compacting recipes are understood to be those that change the 'format' of an item, while not transforming them into something different. Recipes that create barrels or stacked boxes are common examples.

The integration expects a table called `recipes`, which contains a list of names that should be marked as compacting recipes.

#### Example

```lua
remote.add_interface("fp-integration-example-mod", {
    compacting_recipes = (function()
        return {
            version = 1,
            recipes = {"landfill"}
        }
    end)
})
```

### `machine_effects`

**Current version:** `1`, available from `2.1.11`

This integration allows mods to tell Factory Planner about effects they apply to a machine outside of the module system, which it has no way of seeing otherwise. A hidden module inserted into a hidden beacon next to every machine of a given type is the typical case. Factory Planner treats these as an addition to the machine's base effects, meaning they are subject to the machine's effect limits and are shown to the user as machine effects.

This integration is collected per-force, so it's passed a force index and should return what currently applies to that force. Call [`invalidate`](#invalidate) whenever that changes.

The integration expects a table called `effects`, which maps machine names to a table of effects. These are given as floats, in the same format that a module prototype's effects use. Any effect that's left out counts as zero.

#### Example

```lua
remote.add_interface("fp-integration-example-mod", {
    machine_effects = (function(force_index)
        return {
            version = 1,
            effects = {
                ["assembling-machine-2"] = {speed = 0.5, productivity = 0.1}
            }
        }
    end)
})
```

### `overwrite_recipe_picker`

**Current version:** `1`, available from `2.1.11`

This integration enables overwriting Factory Planner's decision tree for determining whether a recipe is able to be chosen in the recipe picker. It runs various checks for whether a recipe is actually usable, but it makes sense to overwrite this in some cases where recipes or technologies are managed by scripting.

This integration is collected per-force, so it's passed a force index and should return what currently applies to that force. Call [`invalidate`](#invalidate) whenever that changes.

The integration expects a table called `recipes`, which maps recipe names to either `true` (always show) or `false` (never show). Any recipe that's left out is judged by Factory Planner's own checks.

Existing production lines using a recipe that is hidden this way are not removed; they are marked as blocked and excluded from the calculation until their recipe becomes obtainable again.

#### Example

```lua
remote.add_interface("fp-integration-example-mod", {
    overwrite_recipe_picker = (function(force_index)
        return {
            version = 1,
            recipes = { ["fast-transport-belt"] = true }
        }
    end)
})
```

### `recipe_substitutions`

**Current version:** `1`, available from `2.1.11`

This integration allows mods to tell Factory Planner that they replaced one recipe with another by scripting, which it has no way of noticing otherwise. Factory Planner hides the replaced recipes from the recipe picker, and migrates any existing production line using one over to its replacement, keeping the line's machine, modules, beacon and fluid temperatures wherever they still apply.

This integration is collected per-force, so it's passed a force index and should return what currently applies to that force. Call [`invalidate`](#invalidate) whenever that changes.

The integration expects a table called `substitutions`, which maps the name of a recipe the force can't obtain right now to the name of the one that stands in for it. Any recipe that's left out is judged by Factory Planner's own checks. A recipe mapping to itself is ignored.

A recipe that appears as a replacement must never also appear as one being replaced. Substitutions are applied in a single step, they are not followed transitively.

Undoing a replacement is done by returning the reverse mapping, which migrates the affected lines back the same way. Note that this is not an undo: a module that the replacement didn't allow is gone for good, as is a machine that had to be swapped out along with it.

#### Example

```lua
remote.add_interface("fp-integration-example-mod", {
    recipe_substitutions = (function(force_index)
        return {
            version = 1,
            substitutions = { ["iron-gear-wheel"] = "iron-gear-wheel-improved" }
        }
    end)
})
```

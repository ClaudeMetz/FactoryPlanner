# Compatibility Interface Docs

Factory Planner offers certain ways to influence its functionality from the outside, as a way to provide improved compatibility with mods making use of custom scripting. This lists and explains these interfaces.

Note that this compatibility interface is currently very limited, but I'm open to expanding it to fit your use case. Just open a Github issue presenting it and we'll go from there.

## Index

- [Runtime integrations](#runtime-integrations)
  - [`overwrite_recipe_picker`](#overwrite_recipe_picker)
- [Static integrations](#static-integrations)
  - [`recycling_recipes`](#recycling_recipes)
  - [`compacting_recipes`](#compacting_recipes)

## Runtime integrations

A runtime integration can be used at any time in the [lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html). It influences Factory Planner from that point on. It's implemented via a [remote interface](https://lua-api.factorio.com/latest/classes/LuaRemote.html) called `"fp-integration"` that mods can call. Details on how to use the individual integrations can be found in dedicated sections below.

All runtime integrations require a `version` integer to be included to indicate the format used. The individual integration docs below indicate which version they describe. They also indicate the first release of Factory Planner that the interface became available on.

Note that anything configured through runtime integrations is reset [on_configuration_changed](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html#on_configuration_changed), and thus needs to be setup again afterwards.

### `overwrite_recipe_picker`

**Current version:** `1`, available from `2.1.1`

This integration enables overwriting Factory Planner's decision tree for determining whether a recipe is able to be chosen in the recipe picker. It runs various checks for whether a recipe is actually usable, but it makes sense to overwrite this in some cases where recipes or technologies are managed by scripting.

The integration expects a table called `recipes`, which maps recipe names to either `true` (always show) or `false` (never show). Writing `nil` removes a previously configured recipe from the list.

#### Example

```lua
remote.call("fp-integration", "overwrite_recipe_picker", {
    version = 1,
    recipes = { ["fast-transport-belt"] = true }
})
```

## Static integrations

A static integration needs to be set up as a [remote interface](https://lua-api.factorio.com/latest/classes/LuaRemote.html) inside the mod that wishes to use it. Factory Planner will then call this interface at specific times to retrieve the integration data. To that end, the interface needs to return a specific format, described for each integration in dedicated sections below.

For Factory Planner to be able to find the remote interface, it needs to follow a specific naming convention: It needs to start with `"fp-integration-"`, followed by the exact internal name of the mod. This is the one called `"name"` in the `info.json` file. The examples below mimmic a mod called `"example-mod"`, thus add an interface called `"fp-integration-example-mod"`.

All static integrations require a `version` integer to be included to indicate the format used. The individual integration docs below indicate which version they describe. They also indicate the first release of Factory Planner that the interface became available on.

Note that mods need to set up their remote interface during the `control.lua` stage of the [lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html), so Factory Planner has access to it at any point it needs to. In addition, if more than one static integration is used, they need to be bundled into the same `remote.add_interface` call.

### `recycling_recipes`

**Current version:** `1`, available from `2.1.1`

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

**Current version:** `1`, available from `2.1.1`

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

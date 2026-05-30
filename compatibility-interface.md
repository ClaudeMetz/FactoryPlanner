# Compatibility Interface Docs

Factory Planner offers certain ways to influence its functionality from the outside, as a way to provide improved compatibility with mods making use of custom scripting. This lists and explains these interfaces.

Note that this compatibility interface is currently very limited, but I'm open to expanding it to fit your use case. Just open a Github issue presenting it and we'll go from there.

## Index

- [Runtime interfaces](#runtime-interfaces)
  - [`overwrite_recipe_picker`](#overwrite_recipe_picker)

## Runtime interfaces

A runtime interface is one that can be used at any time in the [lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html), and which influences Factory Planner from that point on. This is offered through a [remote interface](https://lua-api.factorio.com/latest/classes/LuaRemote.html) called `"fp-integration"`, which contains all the listed methods. Details on how to use them can be found in their respective sections.

All runtime interfaces require a `version` integer to be included to indicate the format used. The individual docs below indicate which version they describe. They also indicate the first release of Factory Planner that the interface became available on.

Note that anything configured through runtime interfaces is reset [on_configuration_changed](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html#on_configuration_changed), and thus needs to be setup again afterwards.

### `overwrite_recipe_picker`

**Current version:** `1`, available from `2.0.51`

This interface enables overwriting the mod's decision tree for deciding whether a recipe is able to be chosen in the recipe picker. Factory Planner runs various checks for whether a recipe is actually usable, but it makes sense to overwrite this in some cases where recipes or technologies are managed by scripting.

The interface expects a table called `values`, which maps recipe names to either `true` (always show) or `false` (never show). Writing `nil` removes a previously configured recipe from the list.

#### Example

```lua
remote.call("fp-integration", "overwrite_recipe_picker", {
    version = 1,
    values = { ["fast-transport-belt"] = true }
})
```

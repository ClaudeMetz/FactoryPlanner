# Data Interface Docs

Factory Planner offers a remote interface to read or write certain parts of its user data. This lists and explains these interfaces.

Note that if there's some data you'd like to see exposed, please open a Github issue and we'll go from there.

## Index

- [`export_current_factory`](#export_current_factory)
- [`export_preferences`](#export_preferences)
- [`import_preferences`](#import_preferences)

## `export_current_factory`

**Availability:** from `2.1.1`

This interface returns the given player's currently selected Factory as a portable table. This uses the same format as Factory Planner's export strings do, but also includes solver results such as machine counts, and products and ingredients.

The interface expects a player index as an argument. If the player doesn't exist, hasn't been initialized yet, or has no factories, it returns `nil`. Otherwise, it returns the factory table (whose format is not documented here).

### Example

```lua
local current_factory = remote.call("fp-interface", "export_current_factory", player.index})
```

## `export_preferences`

**Availability:** from `2.1.1`

This interface returns the given player's preferences as a table. This does not include any prototype-related preferences.

The interface expects a player index as an argument. If the player doesn't exist, or hasn't been initialized yet, it returns `nil`. Otherwise, it returns the preferences table (whose format is not documented here).

### Example

```lua
local preferences_table = remote.call("fp-interface", "export_preferences", player.index})
```

## `import_preferences`

**Availability:** from `2.1.1`

This interface allows overwriting a player's preferences as a table. This does not include any prototype-related preferences.

The interface expects a player index as an argument. If the player doesn't exist, or hasn't been initialized yet, it returns `nil`. Secondly, it expects a table containing the updated preferences (whose format is not documented here). If this table is malformed, an error string is returned. Otherwise, it `true` is returned.

### Example

```lua
remote.call("fp-interface", "import_preferences", player.index, {...}})
```

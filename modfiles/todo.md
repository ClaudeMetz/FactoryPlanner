# TODO

# Verify

- Check whether pollution calculations are still correct
- Check if beacon selector still looks and works correctly
- Check if blueprint in hand still looks correct (when generating blueprint from machines etc)

# Any time

- Check why the example factory doesn't import properly
- Use button's `auto_toggle` argument? Sounds really nice, in combination with `toggle` elsewhere maybe
- Look into using the new sprite button definition style if that's a thing
  - Seems there might be nothing new, but disabling buttons now modifies their icon, which is undesirable in come cases
- Make preferences dialog look less fucked up (also what does 'parameters' mean as a recipe category)
- Figure out how to generate offshore pump prototypes again
- Figure out how energy consumption and drain works in the new API
- Check out how to handle emissions for different pollutant types? Do I just need to show all if applicable?
  - Only implemented `"pollution"` for now
- Redo rocket handling now that they can't take specific items anymore, which hopefully is a simplification
- Check which prototype attributes to use for sorting them in preferences
- Is `base_productivity` not a thing on Entities anymore? If not, remove from code, otherwise migrate
- Are `limitations` on module items not a thing anymore? What replaces that system?
  - `allowed_effects` now a thing on recipes apparently
- Fix _porter.import_factories(), probably by adjusting the factory string
  - Example subfactory also doesn't work, needs some general migration fix it seems
- Holy shit quality fucks up a lot of stuff.
  - Every place I need a property that can be influenced by quality, I can specify that quality.
  - So theoretically every place I use such a prototype I could offer a choice of which prototype to use.
  - Which also means I'd need to keep around a value for every possible quality and account for it everywhere.
  - This is quite insane, so for the first version I'll assume everything has normal quality.

# Waiting on

- Run Factorio with `--check-unused-prototype-data` to clean up the definitions and make sure no functionality was lost
- Uncomment all the `.hidden` uses that were missing from the API

# Release

- Update other language docs for the new `plural_for_parameter` format

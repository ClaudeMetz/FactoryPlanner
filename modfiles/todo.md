# TODO

# Verify

- Check whether shortcut still looks correct, even if disabled
- Check whether pollution calculations are still correct
- Check elements using `fp_scroll-pane_fake_listbox`, `fp_scroll-pane_slot_table` and `fp_sprite-button_group_tab` still look correct
- Check if beacon selector still looks and works correctly
- Check if blueprint in hand still looks correct (when generating blueprint from machines etc)

# Any time

- Figure out how to generate offshore pump prototypes again
- Figure out how energy consumption and drain works in the new API
- Check out how to handle emissions for different pollutant types? Do I just need to show all if applicable?
  - Only implemented `"pollution"` for now
- Is `base_productivity` not a thing on Entities anymore? If not, remove from code, otherwise migrate
- Are `limitations` on module items not a thing anymore? What replaces that system?
- Fix _porter.import_factories(), probably by adjusting the factory string
- Holy shit quality fucks up a lot of stuff.
  - Every place I need a property that can be influenced by quality, I can specify that quality.
  - So theoretically every place I use such a prototype I could offer a choice of which prototype to use.
  - Which also means I'd need to keep around a value for every possible quality and account for it everywhere.
  - This is quite insane, so for the first version I'll assume everything has normal quality.

# Waiting on

- Run Factorio with `--check-unused-prototype-data` to clean up the definitions and make sure no functionality was lost
- Uncomment all the `.hidden` uses that were missing from the API

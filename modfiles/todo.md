# TODO

# Active

# Any time

- Quality effect is multiplied by 10 in machine/beacon dialogs
- Use button's `auto_toggle` argument? Sounds really nice, in combination with `toggle` elsewhere maybe
- Look into using the new sprite button definition style if that's a thing
  - Seems there might be nothing new, but disabling buttons now modifies their icon, which is undesirable in come cases
- Figure out how to generate offshore pump prototypes again
- Figure out how energy consumption and drain works in the new API
- Check out how to handle emissions for different pollutant types? Do I just need to show all if applicable?
  - Only implemented `"pollution"` for now
- Redo rocket handling now that they can't take specific items anymore, which hopefully is a simplification
- Are `limitations` on module items not a thing anymore? What replaces that system?
  - `allowed_effects` now a thing on recipes apparently
  - also effect_receiver :: EffectReceiverPrototype ?
- Fix _porter.import_factories(), probably by adjusting the factory string
  - Example subfactory also doesn't work, needs some general migration fix it seems
- Holy shit quality fucks up a lot of stuff.
  - Every place I need a property that can be influenced by quality, I can specify that quality.
  - So theoretically every place I use such a prototype I could offer a choice of which prototype to use.
  - Which also means I'd need to keep around a value for every possible quality and account for it everywhere.
  - This is quite insane, so for the first version I'll assume everything has normal quality.
- Kinda need the better indication of cyclic recipes for this crap, due to space platform recipes
- Deal with new beacon effect logic -> Think about beacon overload mechanic too
- Mining productivity is now by far not the only productivity modification, so yeah, deal with that
  - Probably just drop the option? (for now?) Also consider locking in the bonus when archiving a factory
- Check on built-in productivity, like for the foundry, doesn't seem like it's applied properly
  - Used to be `base_productivity` but seemingly changed?

# Waiting on

- Find out what's wrong with `wide_as_column_count` on tables, need it almost everywhere
  - Check out the new subtler version of the table containing slots style, could be useful (used in Factoriopedia)
- Uncomment all the `.hidden` uses that were missing from the API
- Item group order getting fixed so picker dialog works properly
- Constant combinator `sections` format rename
- API to open things in Factoriopedia

# Release

- Update other language docs for the new `plural_for_parameter` format
- Verify custom arcosphere logic

# Nice-to-have

- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- The mod should create districts per planet automatically, once districts are implemented. First one should be called Nauvis too
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe

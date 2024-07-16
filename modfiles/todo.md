# TODO

## Active

- deal with new beacon effect logic
- deal with new productivity research (mining kinda separate) #3333FF #3333CC
- check out new global? max productivity, seems to be per recipeProto
- check out max speed no longer being translated to productivity?


- Check on built-in productivity, like for the foundry, doesn't seem like it's applied properly
  - Used to be `base_productivity` but seemingly changed -> now on effect_reciever
- Are `limitations` on module items not a thing anymore? What replaces that system?
  - `allowed_effects` now a thing on recipes apparently
  - also effect_receiver has which kinda effects it allows, which I need to use
- Deal with new beacon effect logic -> Think about beacon overload mechanic too
- Mining productivity is now by far not the only productivity modification, so yeah, deal with that
  - Probably just drop the option? (for now?) Also consider locking in the bonus when archiving a factory
- Also I think excess crafting speed is no longer translated to productivity but works as expected now?
  - Also recipes now have a max productivity instead which I need to cap?

## Any time

- Go over changes so far and pull out anything changelog-worthy
- Use button's `auto_toggle` argument? Sounds really nice, in combination with `toggle` elsewhere maybe
- Look into using the new sprite button definition style if that's a thing
  - Seems there might be nothing new, but disabling buttons now modifies their icon, which is undesirable in come cases
- Figure out how to generate offshore pump prototypes again
- Figure out how energy consumption and drain works in the new API
- Check out how to handle emissions for different pollutant types? Do I just need to show all if applicable?
  - Only implemented `"pollution"` for now
- Kinda need the better indication of cyclic recipes for this crap, due to space platform recipes
- Redo rocket handling now that they can't take specific items anymore, which hopefully is a simplification
  - also there is rocket part productivity now
- Rocket silo launch sequence time now works differently because you can have two rockets at a time
  - still relevant, but only when you can build rockets faster than you launch them
- Mining drills now have a `resource_drain_rate_percent` thing


- Deal with surface conditions for crafting?
- Deal with item spoiling?
- Holy shit quality fucks up a lot of stuff.
  - Every place I need a property that can be influenced by quality, I can specify that quality.
  - So theoretically every place I use such a prototype I could offer a choice of which prototype to use.
  - Which also means I'd need to keep around a value for every possible quality and account for it everywhere.
  - This is quite insane, so for the first version I'll assume everything has normal quality.
- Quality effect is multiplied by 10 in machine/beacon dialogs
  - seems like something that still needs to be worked out https://wubesoftware.slack.com/archives/C12GUBRHS/p1720862186697859
  - also quality calculations are not like other effects probably? Needs custom handling for sure
- Cap quality bonus maybe? Not sure what the limits are, and they might change

## Waiting on

- Find out what's wrong with `wide_as_column_count` on tables, need it almost everywhere
  - Check out the new subtler version of the table containing slots style, could be useful (used in Factoriopedia)
- Uncomment all the `.hidden` uses that were missing from the API
- Item group order getting fixed so picker dialog works properly
- Constant combinator `sections` format rename
- API to open things in Factoriopedia

## Release

- Update other language docs for the new `plural_for_parameter` format
- Custom Arcosphere logic disabled for now
- Beacon Overload functionality disabled for now

## Nice-to-have

- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- The mod should create districts per planet automatically, once districts are implemented. First one should be called Nauvis too
  - In addition or orthogonally, you could set planets on factories, which automatically restricts available recipes? (surface conditions?)
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe
- Replace any machine/beacon/etc buttons with ones that have the standard tooltip.
  - Saves me the hassle of generating them and automatically has the information people expect

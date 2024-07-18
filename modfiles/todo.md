# TODO

## Active


## Any time

- Look into whether slider bugs are fixed now, bother people otherwise. Same for weird custom slider style I use
- Look into using the new sprite button definition style if that's a thing
  - Seems there might be nothing new, but disabling buttons now modifies their icon, which is undesirable in come cases
  - Use button's `auto_toggle` argument? Sounds really nice, in combination with `toggle` elsewhere maybe
- Figure out how to generate offshore pump prototypes again
- Figure out how energy consumption and drain works in the new API
- Check out how to handle emissions for different pollutant types? Do I just need to show all if applicable?
  - Only implemented `"pollution"` for now
- Redo rocket handling now that they can't take specific items anymore, which hopefully is a simplification
  - also there is rocket part productivity now
- Rocket silo launch sequence time now works differently because you can have two rockets at a time
  - still relevant, but only when you can build rockets faster than you launch them
- Mining drills now have a `resource_drain_rate_percent` thing


- Quality is kind of a lot
  - Every place I need a property that can be influenced by quality, I can specify that quality.
  - So theoretically every place I use such a prototype I could offer a choice of which prototype to use.
  - Which also means I'd need to keep around a value for every possible quality and account for it everywhere.
  - Also not sure how the calculations work, or how I should integrate them, with them being probabilities and all.
  - seems like something that still needs to be worked out https://wubesoftware.slack.com/archives/C12GUBRHS/p1720862186697859
  - also quality calculations are not like other effects probably? Needs custom handling for sure
- Item Spoiling - what should my interaction with it be?

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

## Nice-to-have

- The mod should create districts per planet automatically, once districts are implemented. First one should be called Nauvis too
  - In addition or orthogonally, you could set planets/plattform on factories, which automatically restricts available recipes? (surface conditions?)
  - Surface conditions exist on recipes and machines seemingly. Not sure whether to just flag non-working recipes or not allow them
- Replace any machine/beacon/etc buttons with ones that have the standard tooltip.
  - Saves me the hassle of generating them and automatically has the information people expect
- Need indication of cyclic recipes finally, used a lot on the space platform
- Should have the ability to manually configure recipe productivity boni somewhere
- Fix more than one craft per tick being possible, instead of it being translated into productivity

## Ghetto Github Issues

- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe

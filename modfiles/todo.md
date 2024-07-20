# TODO

## Active


## Any time

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
- Sliders still bugged this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Uncomment all the `.hidden` uses that were missing from the API
- Constant combinator `sections` format rename
- API to open things in Factoriopedia
- Disabled sprite buttons fade their icons, can't be turned off?

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
- Show offshore pump ingredients being the tile they need; requires larger refactoring probably
- Add shorthand recipe for 1 complete rocket, instead of needing to add 50 parts. Hard part will be picking an icon for it
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though

## Ghetto Github Issues

- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe
- Use LuaEntityPrototype::type in generator when applicable instead of trying to parse properties -> could break stuff

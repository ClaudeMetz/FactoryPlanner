# TODO

## Active

- In addition or orthogonally, you could set planets/plattform on factories, which automatically restricts available recipes? (surface conditions?)
  - Surface conditions exist on recipes and machines seemingly. Maybe offer toggle on recipe picker to hide/show unbuildable ones
    - Changing location of districts might need to revalidate all the recipes etc to make sure they still work
    - Seems pollution type is tied to space-location, so it'd only need to show the one for each district
- Balance District items against each other? Or show things as products and ingredients if that's the case?
- Should close districts view if any real action is taken in the factory list (select, add, etc)

## Bugs

- Scrap recycling recipe shouldn't be marked as recycling since it's kind of a core recipe
- Recycling recipes seem to follow a different new format for what they produce?
- Agriculture tower recipes not supported - maybe it doesn't use recipes?
- Module defaults-set stuff doesn't refresh module_effects properly
- Translation seems to not reload when loading a save
- Disable SA-specific features by checking feature flags in the right spots

## Uncertainty Sphere

- Quality is kind of a lot
  - Every place I need a property that can be influenced by quality, I can specify that quality.
  - So theoretically every place I use such a prototype I could offer a choice of which prototype to use.
  - Which also means I'd need to keep around a value for every possible quality and account for it everywhere.
  - Also not sure how the calculations work, or how I should integrate them, with them being probabilities and all.
  - seems like something that still needs to be worked out https://wubesoftware.slack.com/archives/C12GUBRHS/p1720862186697859
  - also quality calculations are not like other effects probably? Needs custom handling for sure
- Item Spoiling - what should my interaction with it be?
- Show offshore pump ingredients being the tile they need; requires larger refactoring probably. Not sure.
- Use LuaEntityPrototype::type in generator when applicable instead of trying to parse properties -> could break stuff

## Waiting on

- Sliders still bugged, this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Uncomment all the `.hidden` uses that were missing from the API
- Constant combinator `sections` format rename
- API to open things in Factoriopedia
- Disabled sprite buttons fade their icons, can't be turned off
- Surface prototypes missing surface_properties read for generator, add surfaces to locations properly

## Release

- Update other language docs for the new `plural_for_parameter` format
- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Custom Arcosphere logic disabled for now

## Nice-to-have

- Replace any machine/beacon/etc buttons with ones that have the standard tooltip.
  - Saves me the hassle of generating them and automatically has the information people expect
- Need indication of cyclic recipes finally, used a lot on the space platform
- Should have the ability to manually configure recipe productivity boni somewhere
- Add shorthand recipe for 1 complete rocket, instead of needing to add 50 parts. Hard part will be picking an icon for it
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Fluid temperatures are still a major issue ...
- Need an 'are you sure' dialog for deleting a District, resetting preferences, etc
- Add a district automatically once someone lands on a new planet for the first time, plus space platform
- Look into new display_density_scale thing ideally
- Deleting the non-selected district/factory still sets the context to a neighbor, which is weird

## Low Priority

- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe
- Get rid of player_table.active_factory hack since it's very easy to avoid

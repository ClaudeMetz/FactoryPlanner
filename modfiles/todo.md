# TODO

## Active


## Bugs

- Recycling recipes seem to follow a different new format for what they produce?
- Agriculture tower recipes not supported - maybe it doesn't use recipes?
- Module defaults-set stuff doesn't refresh module_effects properly
- Putting beacon into cursor doesn't seem to fill in modules
- Translation seems to not reload when loading a save

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
- Balance District items against each other? Or show things as products and ingredients if that's the case?
- Disable SA-specific features by checking feature flags in the right spots

## Features

- Surface conditions
  - Districts support planets, how should the surface conditions tie into the factories?
  - Could disallow/hide irrelevant recipes/machines or just warn about them.
  - If I disallow, changing planets needs to remove everything invalid
  - If I warn, I need to permanently mark invalid stuff ideally
  - Every surface seems to have only one pollution type? (`location::pollutant_type`) If true adjust to that
- Allow Factory products to take their amounts from the District's ingredients
  - Not easy since it can result in loops so no definite state can be resolved.
  - Several approaches to solve this, but it's going to be complicated.
- Add feature to transfer items from district to district, mimmicing space platform transfers
- Replace any machine/beacon/etc buttons with ones that have the standard tooltip.
  - Saves me the hassle of generating them and automatically has the information people expect
- Need indication of cyclic recipes finally, used a lot on the space platform
- Should have the ability to manually configure recipe productivity boni somewhere
- Add shorthand recipe for 1 complete rocket, instead of needing to add 50 parts. Hard part will be picking an icon for it
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Fluid temperatures are still a major issue ... (fluoroketone)
- Need an 'are you sure' dialog for deleting a District, resetting preferences, etc
- Add a district automatically once someone lands on a new planet for the first time, plus space platform
- Deleting the non-selected district/factory still sets the context to a neighbor, which is weird

## Low Priority

- Add new view of rockets/timescale, useful for items you need to transfer across planets
  - Needs new view state preferences idea. Could also be timescale/rocket instead
- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe
- Get rid of player_table.active_factory hack since it's very easy to avoid
- Main interface toggles/builds? 4 times when starting a save, which is weird
  - Check refreshes in general, maybe write a tool that flags when multiple refreshes happen in sequence
- Change SimpleItems to be a dict instead of an array so there needs to be no fuss finding stuff
- Look into new display_density_scale thing ideally
- Picker seemingly doesn't care about the item/fluid dichotomy

## Waiting on

- Sliders still bugged, this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Uncomment all the `.hidden` uses that were missing from the API
- Constant combinator `sections` format rename
- API to open things in Factoriopedia
- Disabled sprite buttons fade their icons, can't be turned off
- Surface prototypes missing surface_properties read for generator, add surfaces to locations properly
- Ingredient/Product/etc? definitions might have changed and I use them in my type system
- Base game steals tons of normal key combos which is annoying (ctrl+f among others)

## Release

- Update other language docs for the new `plural_for_parameter` format
- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Custom Arcosphere logic disabled for now

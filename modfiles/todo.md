# TODO

## Active

- Change prototyper.find_prototype to have option to find category only
- Consider a similar method that uses id's to avoid global.prototypes.X
  - Maybe even a combination of both, should you have a category name and proto id etc
  - Make sure to find all the places that could use this

## Bugs

- You can select two of the same module if you want, due to the new quality stuff
  - Can't prohibit two of the same module because they could have different qualities
  - Probably need to remove it again after the fact with a warning message
- Translation seems to not reload when loading a save, maybe other times too
- Warning about serializing lua function, maybe when dialog is open? not sure how this happend

## Uncertainty Sphere

- Quality calculations: not sure how far I want to go with these
  - Could at least give the probabilities maybe? It's a lot of tooltip clutter, and potentially solver clutter
  - There's bigger ideas where you could enter X quality Y items per timescale and it would backsolve it
  - Plus more such ideas, but they seem kinda out there currently, need to play with quality myself first
- Item Spoiling - what should my interaction with it be?
- Disable SA-specific features by checking feature flags in the right spots
- Add a district automatically once someone lands on a new planet for the first time, plus space platform
  - Not sure if I want this, might be overbearing
- Default modules/beacons is awkward with quality since you can't specify it (atm)
  - Feature is still neat, but maybe time to axe it? Or make it work better somehow
- Default machines is awkward with quality as you can't specify it
  - Would be better solved with the in-dialog 'save as default' instead of it being a preference idea
- Not sure what to do with assembling machines fixed_quality and fixed_recipe

## Features

- Move utilities button to factory info, alongside new 'options'/'configuration' dialog, for recipe prod settings
  - Should have the ability to manually configure recipe productivity boni somewhere
  - Or, getting crazy, re-add the production bar above the table and have factory info stuff there
  - Could shuffle more things around, like move buttons back down, other stuff up top, if I have another bar
  - Another advantage is that the factory list on the left can more space for when multiplayer stuff hits
- Agriculture tower recipes not supported - doesn't use recipes I don't think
- Surface conditions, based on Districts
  - It's too messy to not allow condition-incompatible stuff, since it'll need to be addressed on any planet change
  - Instead, mark incompatible recipes/machines red in their dialogs and in the prod table, and disable their line
  - On location change/migration, go over everything and check things, disable if incompatible
  - Maybe have a second flag à la `valid` for this that gets verified in some way.
  - Every surface seems to have only one pollution type? (`location::pollutant_type`) If true adjust to that
- Change SimpleItems to be a dict instead of an array so there needs to be no fuss finding stuff
- Balance District items against each other
- Allow Factory products to take their amounts from the District's ingredients
  - Not easy since it can result in loops so no definite state can be resolved.
  - Just need the simplest version that works for now, so users will have to trigger the infinite loops
    themselves with manual refreshes if they want to, thus also no loop detection for now
  - Not exactly sure on the details of the refresh logic, will find it while implementing
  - Should have a 'multiply District amount by X' variable too so you can overproduce on purpose
  - Alternatively could have a district amount + the normal amount instead, a bit messy but could work well
- Add feature to transfer items from district to district, mimmicing space platform transfers
- Need indication of cyclic recipes finally, used a lot on the space platform
- Add shorthand recipe for 1 complete rocket, instead of needing to add 50 parts. Hard part will be picking an icon for it
- Need an 'are you sure' dialog for deleting a District, resetting preferences, etc
- Make recipe picker icons normal sized (40x40 instead of 36x36)
- Check out if there is any way to use key combos like Q to pick items/entities

## Low Priority

- Make custom tooltips look a bit nicer, maybe look at RB for inspiration or something
- Add new view of rockets/timescale, useful for items you need to transfer across planets
  - Needs new view state preferences idea. Could also be timescale/rocket instead
- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe
- Get rid of player_table.active_factory hack since it's very easy to avoid
- Main interface toggles/builds? 4 times when starting a save, which is weird
  - Check refreshes in general, maybe write a tool that flags when multiple refreshes happen in sequence
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Look into new display_density_scale thing ideally
- Picker seemingly doesn't care about the item/fluid dichotomy
- Finally get rid of generic dialogs, even without the extended features

## Waiting on

- Sliders still bugged, this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Uncomment all the `.hidden` uses that were missing from the API
- Constant combinator `sections` format rename
- API to open things in Factoriopedia
- Disabled sprite buttons fade their icons, can't be turned off
- Surface prototypes missing surface_properties read for generator, add surfaces to locations properly
- Base game steals normal key combos which is annoying (ctrl+f among others)
- No way to show quality on sprite buttons, which is essential in tons of places
  - Same thing for quality color, which should be used in relevant tooltips
- Special quality attributes for beacons and miners not available on LuaQualityPrototype yet

## Release

- Update other language docs for the new `plural_for_parameter` format
- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Custom Arcosphere logic disabled for now

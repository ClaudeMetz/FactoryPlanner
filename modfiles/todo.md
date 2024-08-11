# TODO

## Active


## Bugs

- You can select two of the same module if you want, due to the new quality stuff
  - Can't prohibit two of the same module because they could have different qualities
  - Probably need to remove it again after the fact with a warning message
- Translation seems to not reload when loading a save, maybe other times too
- Warning about serializing lua function, maybe when dialog is open?
  - Steve ran into with beacon dialog open, plus a module chooseElem open
- Rocket silo power usage seems very low, likely doesn't consider launch usage
- Differences between trad and matrix solver related to quality
  - String: eNrtV01rGzEQ/S86e42dOIUs9NJDTy0Uegxm0UqzzoA+NpLWrTH+7x2tZHdtJ6QtJrjtgg/Wm+830sPeMvjeWhcqbaWHwMotq7kHVrL59GY6n7MJAwVrHkAWjqPyQ0ujsKbz/f2UPjMCnjquMGyOfLgI1m1axY0Bly0LMviWCyj4alBrt3dHoDoPWyYU97Hix5SEogzXMeABA+j3rbMCvEezKjqDYUn2gBq84Iqc3s0mrFYdtA5NoCxbSm9siKkZeVKw7EQ4LvQlgckcbKQjVzypRR6CSFnFrkoWuyFE8sCrsGkhQz6OibpV2CBIVgbXATUhoUEDsqpjKNe2MzGdg6cOHcEZKe9muyUNZNuqUda62MuBjx6YMNoMKFbO6RtlPB7lEyF9WoEtVK+PM2w+Bb3QfiYOrdm7JyRWk5aKlg1XHiaMloZrSHEUBk6ACf3C5zPajebiMfY4mOtzhs7pp0sogrOarwwEFEW8TydLyC4GhS++YXgsGtWhPJksF31htHx/z9hSsAIjeX8Dh9mSP76UrrE0cqVQE8GZBXpmnYIqP7XD3D36FeJEyeN4l8n+/K3sd7GmrosUWdwe0zJ0OSUjl3oLLg63erfc0bEGLqwZcvAhIecz1nvDsFoC37b1xcXX51sgXX1+b73tChZ2kxYmrNYQz4xk+ldVhss1N4JGFOhE98/JzKgto7ZcqPXbUVt+U1t+vsNRXUZ1GdVl/OVySXUR3If450jYlt58IXjd03Dd+tLQ3LJna7ANDYEr1bnVZhSU6xKUxd8rKHejoPyhoKA7W+AoJKOQjELynwsJAcvdD1NMMyY=

## Uncertainty Sphere

- Quality calculations: not sure how far I want to go with these
  - Could at least give the probabilities maybe? It's a lot of tooltip clutter, and potentially solver clutter
  - There's bigger ideas where you could enter X quality Y items per timescale and it would backsolve it
  - Plus more such ideas, but they seem kinda out there currently, need to play with quality myself first
- Item Spoiling - what should my interaction with it be?
- Default modules/beacons is awkward with quality since you can't specify it (atm)
  - Feature is still neat, but maybe time to axe it? Or make it work better somehow
- Default machines is awkward with quality as you can't specify it
  - Would be better solved with the in-dialog 'save as default' instead of it being a preference idea

## Features

- Agriculture tower implementation
  - Having a machine number just doesn't make sense for it, so need to adjust solver and UI
    to allow for machines that just don't have a machine amount. Useful for oil mining too.
  - Missing energy and pollution production, is different to normal entities
- Better infinite mining drill support
  - Kind of incredibly annoying, since there is nothing I can really calculate about it
  - Could still make it so it shows the oil patch as an ingredient without amount (same for offshore pumps)
- Move utilities button to factory info, alongside new 'options'/'configuration' dialog, for recipe prod settings
  - Should have the ability to manually configure recipe productivity boni somewhere
  - Or, getting crazy, re-add the production bar above the table and have factory info stuff there
  - Could shuffle more things around, like move buttons back down, other stuff up top, if I have another bar
  - Another advantage is that the factory list on the left can more space for when multiplayer stuff hits
  - Could drop the per-factory timescale setting and just have it be global. Makes layout easier too
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
- Need an 'are you sure' dialog for deleting a District, resetting preferences, etc
- Make recipe picker icons normal sized (40x40 instead of 36x36)
- Check out if there is any way to use key combos like Q to pick items/entities
- Disable SA-specific features by checking feature flags in the right spots
- Convert solver to be timescale-independent, and only apply timescale when displaying results
  - Basically means calculate everything as /s, like I do for Districts already

## Low Priority

- Make custom recipe tooltips look a bit nicer, maybe look at RB for inspiration or something
- Add new view of rockets/timescale, useful for items you need to transfer across planets
  - Needs new view state preferences idea. Could also be timescale/rocket instead
- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- Have separate methods for each GUI action instead of a tree. Needs some prep methods sometimes maybe
- Get rid of player_table.active_factory hack since it's very easy to avoid
- Main interface toggles/builds? 4 times when starting a save, which is weird
  - Check refreshes in general, maybe write a tool that flags when multiple refreshes happen in sequence
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Picker seemingly doesn't care about the item/fluid dichotomy
- Finally get rid of generic dialogs, even without the extended features
- Mark entity-type item buttons better visually, somehow
- When context menus come in, make sure to filter actions properly for all item buttons
  - This is a bit messy with entity-type items currently and can't easily be fixed atm
- Come up with an icon for effects that are limited up or down, instead of saying '(limited)'

## Waiting on

- Sliders still bugged, this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Base game steals normal key combos which is annoying (ctrl+f among others)
- Uncomment all the `.hidden` uses that were missing from the API
- Constant combinator `sections` format rename
- API to open things in Factoriopedia
- Disabled sprite buttons fade their icons, can't be turned off
- Surface prototypes missing surface_properties read for generator, add surfaces to locations properly
- No way to show quality on sprite buttons, which is essential in tons of places
  - Same thing for quality color, which should be used in relevant tooltips
- Plant harvest_emissions and AgriTower growth_grid_tile_size are missing
- RocketSiloRocket::research_products missing from API
- No way to read quality color for use in tooltips

## Release

- Update other language docs for the new `plural_for_parameter` format
- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Custom Arcosphere logic disabled for now

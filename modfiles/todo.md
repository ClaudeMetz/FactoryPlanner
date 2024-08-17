# TODO

## Active

- Should have the ability to manually configure recipe productivity boni somewhere, probs in utility dialog

## Bugs


## Uncertainty Sphere

- Quality calculations: not sure how far I want to go with these
  - Could at least give the probabilities maybe? It's a lot of tooltip clutter, and potentially solver clutter
  - There's bigger ideas where you could enter X quality Y items per timescale and it would backsolve it
  - Plus more such ideas, but they seem kinda out there currently, need to play with quality myself first
- Default modules/beacons is awkward with quality since you can't specify it (atm)
  - Feature is still neat, but maybe time to axe it? Or make it work better somehow
- Default machines is awkward with quality as you can't specify it
  - Would be better solved with the in-dialog 'save as default' instead of it being a preference idea

## Features

- Agriculture tower implementation
  - Having a machine number just doesn't make sense for it, so need to adjust solver and UI
    to allow for machines that just don't have a machine amount. Useful for oil mining too.
  - Missing energy and pollution production, is different to normal entities
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
  - In addition, it would be good if the mod could calculate your rocket and platform needs for the given items
  - Not super simple, needs constraints given by the user, like platform specs, and maybe others
  - Otherwise there won't be a unique solution. Kinda orthogonal in general, but would be helpful to have
- Need an 'are you sure' dialog for deleting a District, resetting preferences, etc
- Check out if there is any way to use key combos like Q to pick items/entities
- Disable SA-specific features by checking feature flags in the right spots

## Low Priority

- Add calculator window - button in main and compact windows, with keyboard shortcut
  - Shortcut should work from anywhere. Calculator needs to be independent window pretty much, kinda tricky
  - UI just simple but nice, with history. Use evaluate_expression for calculation, making things easy
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
- Rocket silo power usage seems very low, likely doesn't consider launch usage
- Finally get rid of generic dialogs, even without the extended features
- Mark entity-type item buttons better visually, somehow
- When context menus come in, make sure to filter actions properly for all item buttons
  - This is a bit messy with entity-type items currently and can't easily be fixed atm
  - Also drop the tutorial dialog entirely, along with the example factory and everything
  - Also use them to quick-change default belts on the view, for example
- Come up with an icon for effects that are limited up or down, instead of saying '(limited)'
  - Could use the arrows that have a floor above/below them to indicate this
  - Also move the other effect capping from solver stuff over to the part the user sees
- Item Spoiling - Not super much to do without a lot of effort.
  - Could do a thing where the user enters the time between steps and it takes the spoilage that incurrs into account
  - Maybe some other stuff too, but I'll have to play with it to figure this out. Low priority anyways
- Better infinite mining drill support
  - Kind of incredibly annoying, since there is nothing I can really calculate about it
  - Could still make it so it shows the oil patch as an ingredient without amount (same for offshore pumps)
- Turn item spoilage results into recipes since mods will use that as a critical path for sure
  - Kinda annoying since it doesn't use machines, just times, so the recipes would be very near useless
- Preferences export would be great. Maybe without migration if that makes it much easier

## Waiting on

- Sliders still bugged, this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Uncomment all the `.hidden` uses that were missing from the API
- Constant combinator `sections` format rename
- API to open things in Factoriopedia
- Disabled sprite buttons fade their icons, can't be turned off
- No way to show quality on sprite buttons, which is essential in tons of places
  - Same thing for quality color, which should be used in relevant tooltips
- No way to read quality color for use in tooltips
- global_effects on planets, yet another effect that needs to be considered
- game.evaluate_expression should not error but return something else if expression is invalid

## Release

- Update other language docs for the new `plural_for_parameter` format
- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Update mod descriptions to mention SA/2.0 general compatibility
- Custom Arcosphere logic disabled for now

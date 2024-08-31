# TODO

## Active


## Bugs


## Uncertainty Sphere

- Quality calculations: not sure how far I want to go with these
  - Quality odds for products - that's kinda dumb without items themselves supporting quality, soo idk
    - Also solver doesn't support this kinda stuff atm anyways, needs rewrite
  - There's bigger ideas where you could enter X quality Y items per timescale and it would backsolve it
  - Plus more such ideas, but they seem kinda out there currently, need to play with quality myself first
- Better infinite mining drill support
  - Kind of incredibly annoying, since there is nothing I can really calculate about it
  - Could still make it so it shows the oil patch as an ingredient without amount (same for offshore pumps)

## Features

- Change SimpleItems to be a dict instead of an array so there needs to be no fuss finding stuff
- Balance District items against each other
- Allow Factory products to take their amounts from the District's ingredients
  - Not easy since it can result in loops so no definite state can be resolved.
  - Just need the simplest version that works for now, so users will have to trigger the infinite loops
    themselves with manual refreshes if they want to, thus also no loop detection for now
  - Not exactly sure on the details of the refresh logic, will find it while implementing
  - Should have a 'multiply District amount by X' variable too so you can overproduce on purpose
  - Alternatively could have a district amount + the normal amount instead, a bit messy but could work well
- Make recalculate_on_factory_change a factory property, not a UI one
  - Also set factories to be recalculated when a prod research finishes
- Add feature to transfer items from district to district, mimmicing space platform transfers
  - In addition, it would be good if the mod could calculate your rocket and platform needs for the given items
  - Not super simple, needs constraints given by the user, like platform specs, and maybe others
  - Otherwise there won't be a unique solution. Kinda orthogonal in general, but would be helpful to have
- Need an 'are you sure' dialog for deleting a District, resetting preferences, etc
- Disable SA-specific features by checking feature flags in the right spots
- Turn item spoilage results into recipes since mods will use that as a critical path for sure
  - Kinda annoying since it doesn't use machines, just times, so the recipes would be very near useless
  - Could use 'time' as a custom ingredient on an otherwise blank line

## Low Priority

- Add calculator window - button in main and compact windows, with keyboard shortcut
  - Shortcut should work from anywhere. Calculator needs to be independent window pretty much, kinda tricky
  - UI just simple but nice, with history. Use evaluate_expression for calculation, making things easy
- Adjust utility dialog handcrafting to behave like vanilla crafting does in all ways
- Get rid of player_table.active_factory hack since it's very easy to avoid
- Main interface toggles/builds? 4 times when starting a save, which is weird
  - Check refreshes in general, maybe write a tool that flags when multiple refreshes happen in sequence
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Rocket silo power usage seems very low, likely doesn't consider launch usage
- When context menus come in, make sure to filter actions properly for all item buttons
  - This is a bit messy with entity-type items currently and can't easily be fixed atm
  - Also drop the tutorial dialog entirely, along with the example factory and everything
  - Also use them to quick-change default belts on the view, for example
- Item Spoiling - Not super much to do without a lot of effort.
  - Could do a thing where the user enters the time between steps and it takes the spoilage that incurrs into account
  - Maybe some other stuff too, but I'll have to play with it to figure this out. Low priority anyways
- Preferences export would be great. Maybe without migration if that makes it much easier
- Agriculture tower implementation
  - Missing energy and pollution production, is different to normal entities
- More stuff with technologies
  - Could order recipes by technology difficulty - not sure how to determine that
  - Could hide items that are not currently craftable
- Make technology prototypes into their own generator category and make use of them via the loader
- Try using flib's built-in translation/search feature instead of doing it myself, saves me having it in global
- Don't aggregate entity type items to the top
- Improve performance by not making item_views.process iterate the prefs every time

## Waiting on

- Sliders still bugged, this is stupid https://forums.factorio.com/viewtopic.php?p=516440#p516440
- Constant combinator `sections` format rename
- Some prototype filters still don't support `hidden` properly
- API to open things in Factoriopedia
- Disabled sprite buttons fade their icons, can't be turned off
- No way to show quality on sprite buttons, which is essential in tons of places
  - Same thing for quality color, which should be used in relevant tooltips
- No way to read quality color for use in tooltips
- global_effects on planets, yet another effect that needs to be considered
- game.evaluate_expression should not error but return something else if expression is invalid
- Ask about whether hover key combos would be possible
  - Could imitate it by keeping track of hover states myself, wouldn't be too horrible

## Release

- Update other language docs for the new `plural_for_parameter` format
- Write changelog description for districts
- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Update mod descriptions to mention SA/2.0 general compatibility
- Sort out Github board for done tasks and deal with pending reports

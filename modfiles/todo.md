# TODO

## Active


## Bugs


## Features

- New defaults section should just be buttons, not checkboxes+confirm. Also make sure it never scrolls
  - Also, make defaults section foldeout more of a button
- Adopt new rocket silo recipes, and drop research rocket one
- Add floating text for all actions that are taken that are not possible
  - Ideally the tooltips and context menu wouldn't show them, but that is tricky
  - It's actually kinda confusing that it shows impossible actions now, should really fix that

## Low Priority

- Rocket silo power usage seems very low, likely doesn't consider launch usage
- Agriculture tower implementation
  - Missing energy and pollution production, is different to normal entities
- Context menu to change belt directly on belt view button
- Replace "can't craft X on this location" notice with the planets it can be crafted on, like vanilla
- FP apparently recipe item amounts are ints and should be floored? Wtf?
  https://discord.com/channels/1214952937613295676/1281881163702730763/1294182548251086901
- Quality module effects are clamped weirdly because of the division by 10 (see leg. quality module)
- Could use icons for control, shift, etc for context menus to make them smaller
- Add support for belt stacking to belt throughput view
  - Kinda need it for product amounts too ideally, which makes it annoying
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Better icons for custom recipes - mining, spoiling, etc
- Could now store blueprints from the library I think
- Try using flib's built-in translation/search feature instead of doing it myself, saves me having it in global
- Preferences export would be great. Maybe without migration if that makes it much easier
- Main interface toggles/builds? 4 times when starting a save, which is weird
  - Check refreshes in general, maybe write a tool that flags when multiple refreshes happen in sequence

## Waiting on

- API to open things in Factoriopedia
  - Hide feature if it's not present for release
- No way to show quality on sprite buttons, which is essential in tons of places
  - Seemingly the hacky way to add a sprite to the button does not work, oof
  - Same thing for quality color, which should be used in relevant tooltips
- Ask about whether hover key combos would be possible
  - Could imitate it by keeping track of hover states myself, wouldn't be too horrible

## Release

- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Update mod descriptions to mention SA/2.0 general compatibility
- Sort out Github board for done tasks and deal with pending reports

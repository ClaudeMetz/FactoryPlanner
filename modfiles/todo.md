# TODO

- New defaults section should just be buttons, not checkboxes+confirm. Also make sure it never scrolls
  - Also, make defaults section foldeout more of a button
- Add floating text for all actions that are taken that are not possible
  - Ideally the tooltips and context menu wouldn't show them, but that is tricky
  - It's actually kinda confusing that it shows impossible actions now, should really fix that

## Low Priority

- Rocket silo power usage seems very low, likely doesn't consider launch usage
- Agriculture tower implementation
  - Missing energy and pollution production, is different to normal entities
- Replace "can't craft X on this location" notice with the planets it can be crafted on, like vanilla
- FP apparently recipe item amounts are ints and should be floored? Wtf?
  https://discord.com/channels/1214952937613295676/1281881163702730763/1294182548251086901
- Quality module effects are clamped weirdly because of the division by 10 (see leg. quality module)
- Could use icons for control, shift, etc for context menus to make them smaller
- Note when rocket silo launch time becomes a problem for speed; it's not at lower speeds
  - Is quite a complicated feature, especially when productivity is involved. Probably do need it though
- Better icons for custom recipes - mining, spoiling, etc
- Could now store blueprints from the library I think

## Release

- Update screenshots, maybe for SA even? Or some of both non-SA and SA?
- Sort out Github board for done tasks and deal with pending reports

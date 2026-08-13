# TODO
- [ ] Scheduler Refactor -> Modularity and functionality
  - Lifecycle hooks
  - Rules for scheduler
- [ ] Loot Tables either via vanilla API or self-implementation
- [ ] Debug Commands -> Scheduler (.List(); .Timer())
- [ ] If possible, track and clean up zombies from events as well to avoid accumulation

# Content Creation
- [ ] Sounds for all events
- [ ] Models for all events

# Event Ideas
- [ ] Using Campers! a camping zone event (people asking for help on radio)
- [x] Using KI5 military vehicles a military convoy crash / ambush
- [ ] Smaller overturned National Guard truck
- [ ] Military / Humanitarian Supply Crate Drop
- [ ] Heli Crash
- [ ] Plane Crash
- [ ] Hidden Stashes
- [ ]


now there s another bug we ve gotta solve, in singleplayer we can clean up events even after rejoining the save, or right away or whenever, but in multiplayer there seems to be an issue, if an admin .spawn an event, leaves the nrejoins and tries clean() it leaves the vehicles behind. this might be an issue only for the cleitn sent .clean command ? im not sure
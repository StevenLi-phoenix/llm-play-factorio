# Space Age tooling for factorio-mcp

Goal of a Space Age run: a space platform reaches the Solar System Edge (`space-finish-script`, which watches
`on_space_platform_changed_state` for `last_visited_space_location == "solar-system-edge"`). The edge opens with the
`promethium-science-pack` research, which needs every science pack, `fusion-reactor` and `biter-egg-handling`
(captured biter spawner, so Nauvis keeps peaceful biters).

## Engine facts (tested on the dev server, 2.0.77)

- `force.create_space_platform{name, planet, starter_pack}` makes a platform in state `waiting_for_starter_pack`.
  A rocket silo holding a `space-platform-starter-pack` in its rocket launches it by itself once the rocket is
  ready; the platform then has a hub at (0,0) on surface `platform-N` with 10x10 foundation, paused, no schedule.
- The hub builds ghosts on its surface from its own inventory (tile ghosts of `space-platform-foundation`,
  entity ghosts). No robots are involved. Ghosts that collide with the hub or stand on empty space never build,
  so placement must be checked before ghosting.
- A rocket with no destination and no platform comes back down; `on_rocket_launched` still fires.
- A character rides a rocket with `silo.launch_rocket({type = defines.cargo_destination.station, station = hub},
  character)`. It arrives inside the hub at (0,0) on the platform surface. (`type = space_platform` is only for
  starter packs; with it the launch is refused.)
- `hub.create_cargo_pod()` + `pod.set_passenger(character)` + `pod.cargo_pod_destination = {type = surface,
  surface = <planet>, position = ...}` drops a character to a planet. A character that arrived by rocket cannot
  be set as passenger or teleported (it stays parked in the hub); a character created on the platform surface
  can. The drop tool therefore re-creates the parked body (same name record, same inventory) and boards that.

## Tools (factorio-mcp 0.3.0 – 0.3.12)

All of these shipped and were used in run 4.

| tool | what it does |
|---|---|
| `platform_order` | order a new platform above the character's planet (waits for a starter pack from a silo) |
| `platforms` | every platform: state, location or connection + distance, speed, schedule, hub contents, open ghosts |
| `platform_build` | ghost entities and foundation tiles on a platform, each checked first; reports rejects |
| `platform_deconstruct` | order deconstruction in an area of a platform (optionally only some entity names) |
| `platform_configure` | recipe, inserter / collector filters and direction of one platform entity or ghost |
| `platform_requests` | hub logistic requests (what rockets bring up), with the planet to import from |
| `platform_schedule` | stops (planets) with wait conditions; pause / unpause |
| `landing_pad_requests` | what a cargo landing pad asks parked platforms to drop |
| `launch_rocket` `platform=` | deliver a silo's cargo into a parked platform's hub |
| `ride_rocket` | walk to a ready silo and ride its rocket to a platform hub |
| `drop_to_planet` | from a platform in orbit, drop the character to that planet's surface |
| `place_tiles` | landfill, concrete and soil from the pocket (planets, not platforms) |
| `set_filters`, `chest_requests`, `equip` (armor grid) | filters on planets, requester/buffer chests, power armor |

Read tools (`scan_area`, `export_blueprint`, `render-area`) work on the character's current surface. There is no
`surface` argument, so a character on Nauvis cannot inspect a platform's entities except through `platforms`.

## Platform facts learned in run 4

- **Crushers.** A crushing recipe returns its chunk only part of the time (metallic crushing: 20 iron ore, chunk
  back at p = 0.2). A crusher therefore needs a collector feeding it. A chunk loop with no collector dies out.
- **Collectors.** Inserters cannot put a chunk into a collector; the collector refuses it. The outermost column of a
  collector must hang over void (the floor edge cuts through it).
- **The hub must not fill.** Crusher products sent into the hub fill it, and then nothing works: crushers stop,
  deconstruction stalls (the hub cannot take the returns), there is no ice, so no water, fuel or oxidizer, and a
  ship cannot leave its orbit. Feed each crusher's product straight into the plant that uses it, so a full chain
  backs up in the machines instead of the hub.
- **Asteroids hit parked platforms too.** Two platforms (eta paused over Fulgora, zeta in flight with a character
  aboard) were destroyed with no turrets or no ammo. Solar panels go first, then the hub. Every platform needs gun
  turrets on the front and sides with belt-fed ammo before it leaves, and before it sits in orbit for long.
- **Floor ghosts.** A lone foundation ghost with no floor north or south of it never builds. Lay floor outward from
  the existing floor, in blocks. A building ghost that never builds usually has an old entity in the way.
- **Reach.** A character in the hub reaches about 10 tiles from (0,0). Beyond that, use platform_build and
  platform_deconstruct (freighter-4 used them out to ~17 tiles).
- **Silos and pads.** Only inserters load a silo's rocket; robots do not. A parked platform's hub drains into any
  landing pad below that requests matching items, chunks included. A pad request does nothing once the pad holds
  the requested amount. landing_pad_requests works only while the character stands on that planet.
- **Riders.** A character's pocket is not weight-limited while riding a rocket; the rocket cargo is.

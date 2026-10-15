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

## Planned tools

| tool | what it does |
|---|---|
| `platform_order` | order a new platform above the character's planet (waits for a starter pack from a silo) |
| `platforms` | every platform: state, location or connection + distance, speed, schedule, hub contents, open ghosts |
| `platform_scan` / `surface` on read tools | scan_area, export_blueprint, render-area on a platform surface |
| `platform_build` | ghost entities and foundation tiles on a platform, each checked first; reports rejects |
| `platform_deconstruct` | order deconstruction in an area of a platform |
| `platform_configure` | recipes, inserter / collector filters, on a platform entity |
| `platform_requests` | hub logistic requests (what rockets bring up) |
| `platform_schedule` | stops (planets) with wait conditions; pause / unpause |
| `ride_rocket` | walk to a ready silo and ride its rocket to a platform hub |
| `drop_to_planet` | from a platform in orbit, drop the character to that planet's surface |

# The House and the hand

The apartment, casino and rest room now have complete colliding shells, ceilings,
framed windows, dusk views and different materials/lighting. Dressing is generated
by `environment/house_environment.gd` when `world.tscn` runs; it does not appear
as baked nodes in the scene editor. The original elevator and terminal paths are
preserved. Reposition authored controls in the scene; change dressing/layout
constants in the builder. Every peer builds identical named prop nodes.

## Story through the rooms

- **Apartment 4B:** overdue rent, patched sofa, cheap bed, packing boxes, torn rug,
  scattered bills, peeling paint and a boarded window. The four friends are
  hungry tenants tempted by the free-wings contract. Their room has practical,
  mismatched furniture rather than casino luxury.
- **The Gilded Coop:** green walls, brass columns and table trim, marble-style
  tiles, a central carpet, warm chandeliers, lounge furniture and coffee service.
  The two tables face the entrance at local `(-5, 0.5, 4)` and `(5, 0.5, 4)`,
  rotated 180 degrees, with space around keypads and a clear route to the lift.
- **Courtesy break:** institutional lighting, ordinary chairs and coffee. The
  staff memo explains that the extra life is a harsh accounting reset, not a refund.

Seven readable lore plaques explain movement, LAN setup, the shared debt, table
rules, quota, courtesy life and carrying. Aim at a plaque and press E or left
click. E/Escape folds it; mouse wheel and Page Up/Down scroll longer text. Movement
and look are locked while reading; the multiplayer day clock continues to run.

## Interaction and controls

| Action | Input / behavior |
| --- | --- |
| Aim | Persistent center dot; focused interactives change it to a gold cross |
| Identify / interact | A local amber material overlay highlights the aimed object; E/LMB prompt names it |
| Pick up | E/LMB on a small object, within 3 meters of the local ray |
| Inventory | One shared physical object per player; no pocket storage |
| Drop | G |
| Throw | Hold RMB, release to throw; 1.25 seconds reaches maximum charge |
| Push | Walk into a loose prop, or E/LMB a larger pushable furnishing |

Objects include imported moving boxes, a radio, pillow, chairs/stool, and
procedural cups, chips, takeaway carton and a brass paperweight. These are play
props, not currency, consumables, weapons or damage sources. They do not affect
wallet accounting. The HUD shows the held object, charge meter, day and courtesy
life. Highlight overlays restore the original material when focus moves away.

## Multiplayer and lifecycle

`interaction/physics_prop.gd` runs rigid-body physics only on the host. Clients
freeze their bodies and interpolate 15 Hz transform snapshots. Reliable holder
messages lock ownership, disable carried collisions and restore loose collisions
on release. Held objects follow the replicated head pose; a short obstruction ray
keeps the held center away from walls.

Pickup RPCs derive sender identity, require roster membership and host-side range
and line of sight. A host search across props enforces one occupied hand, including
simultaneous requests. Drop/charge/throw require the current holder. Charge time
is measured on the host, not submitted by a client. Launch speed grows from 3 to
14 m/s and caps after 1.25 seconds. Push impulses are throttled per object.

Disconnect drops the held object. Elevator travel leaves belongings in the old
room, avoiding props being dragged through fades. Session reset restores props to
their home transforms. A prop falling below Y=-10 returns home. This does not add
player combat, stun/carry, authoritative movement validation or full anti-cheat.
Physics snapshots have no prediction/rollback; latency and four-player clutter
still need human LAN testing.

## Assets

Thirteen unchanged GLBs from **Kenney Furniture Kit 2.0** are included under CC0,
with the original license, source record and SHA-256 manifest in
`assets/kenney/furniture/`. The subset totals about 144 KiB. Architecture,
sky, dressing marks and lore are project-authored. See [ASSETS.md](ASSETS.md).

## Verification

Run the existing `tests/run_checks.ps1` with the Godot 4.7.1 console executable.
It now includes `test_house.tscn` and a second full-world ENet host/client pair on
UDP **17778**, in addition to the Cluckjack tests on 17777. The new suite checks
shell collisions, clear lift openings, table spacing, pickup reach/occlusion,
single-slot enforcement, real input-action dispatch, charge cap, drop/reset/
disconnect recovery, prop respawn and lore input release. Headless displays cannot
capture a cursor; carry input tests dispatch to the same input helper after that
gate. The network test uses production props and world/player spawning.

For rendered QA, create an output directory, then run (without `--headless`):

```powershell
& 'C:/Program Files/Godot/Godot_v4.7.1-stable_mono_win64_console.exe' --path dev-fowl-play --resolution 1440x900 res://tests/capture_house.tscn -- C:/absolute/existing/output-directory
```

This saves apartment, casino, rest, focus, lore and carry PNGs and exits. The capture uses
an in-memory generic nickname and does not change saved user settings. Forward+
D3D12 captures were inspected on an RTX 3050 Ti. Compatibility rendering also
produced the views, but this Godot/driver combination reported two texture cleanup
warnings at process shutdown; the configured Forward+ renderer did not.

Recorded checks on 10 November 2026: **2,042 Cluckjack checks plus 36 room/hand
checks passed**, as did both ENet pairs and the main-scene smoke run. The 36
room/hand checks also passed in a rendered Forward+ run through the actual cursor
and input gate. Captures were inspected at 1440x900 and 800x600; a `carry.png`
capture additionally shows an occupied hand and partially charged throw meter.

Before release, manually test four-player LAN pushing/throwing under latency,
carry near every wall and lift, normal-camera reach at both tables, reading at
small window sizes and a complete ten-day run. Existing font provenance and
minimum hardware targets remain open. No new performance or fun claims are made.

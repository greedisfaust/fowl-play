# ENVIRONMENT_MIGRATION.md — inventory of `house_environment.gd`

**Purpose (brief §3.1):** record every text, number, color, shader line, prop, plaque, light, and piece of furniture that `environment/house_environment.gd` builds, **before** anything is removed. This is the source of truth for hand-building the world in editor scenes. Nothing is deleted from the script until it is reproduced here (and, for rooms, re-built as a scene instance).

**Status:** snapshot of `house_environment.gd` at commit `f994c58` (Phase 2 foundation). `house_environment.gd` is NOT yet deleted. Migration order: Apartment → Rest → Casino (one room at a time, brief §3.5).

---

## Node-path contracts (kept unchanged)

These paths must remain valid for `world.gd` and the tests:

- `Apartment`, `Casino`, `Rest` (Node3D at x = 0, 100, 50 respectively)
- `Apartment/Elevator`, `Rest/Elevator`, `Casino/Elevator`
- `Apartment/NicknameTerminal`, `Apartment/JoinTerminal`, `Apartment/LobbyConsole`, `Apartment/ColorBoard`, `Apartment/PlayerBoard`
- `Rest/StatusBoard`
- `Spawn` markers (inside each room)
- `Casino/ChickenCross`, `Casino/Cluckjack`
- `Players`, `MultiplayerSpawner` (spawn path `../Players`)
- `HUD`, `WorldEnvironment`, `DirectionalLight3D`
- `House` node (removed only when `house_environment.gd` is deleted)

---

## Sky / environment (from `_sky()`)

| Item | Value |
|------|-------|
| Sky type | `ProceduralSkyMaterial` + `Sky` |
| Sky top color | `Color("121d35")` |
| Sky horizon color | `Color("94766c")` |
| Ground bottom color | `Color("101b28")` |
| Ground horizon color | `Color("94766c")` |
| Ambient light source | `Environment.AMBIENT_SOURCE_COLOR` |
| Ambient light color | `Color("8b9ea7")` |
| Ambient light energy | `0.35` |
| DirectionalLight3D energy | `0.35` |

**Floor shader** (`FLOOR_SHADER` inline string) — extract to `res://shaders/floor.glshader` when rebuilding rooms:

```glsl
shader_type spatial;
varying vec3 world;
uniform vec4 base : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform bool marble = false;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 tile = floor(world.xz * (marble ? vec2(0.65) : vec2(2.0, 0.4)));
    float shade = mod(tile.x + tile.y, 2.0) * 0.1;
    float wear = sin(world.x * 31.0 + sin(world.z * 9.0)) * 0.025;
    vec2 grout = fract(world.xz * (marble ? vec2(0.65) : vec2(2.0, 0.4)));
    float joint = step(0.98, max(grout.x, grout.y));
    ALBEDO = base.rgb * (0.87 + shade + wear - joint * 0.35);
    ROUGHNESS = marble ? 0.28 : 0.92;
}
```

Colors used in the script:
- `BRASS` = `Color("bca166")`
- Wall fancy = `Color("243b36")`, wall plain = `Color("77766b")`
- Trim fancy = `BRASS`, trim plain = `Color("444a43")`
- Roof fancy = `Color("242e2c")`, roof plain = `Color("585c52")`
- City = `Color("26333e")`, city windows = `Color("b99663")`

---

## Room: Apartment (`_apartment()`)

**Design direction (current):** Furniture and lore plaques are **removed** from the Apartment build. Instructions/lore/tutorial will be delivered via a TV/slideshow screen device instead of `LorePlaque` plaques. That device is TBD — do not add plaques or furniture to the Apartment scene.

**Shell:** `_shell(room, 12, 12, 3.4, floor_y=0, fancy=false, north_door=false)`
- Walls/trim/roof/plain materials as above
- Window frames + panes on both side walls
- City silhouette boxes on both outer sides

**Floor:** `_floor(room, Color("675745"))`

**Text (Label3D):**
1. "APARTMENT 4B" — pos (0, 2.9, -5.8), pixel_size 0.003, font_size 115, color `d8d0b2`, yaw 0
2. "Four names. One overdue lease." — pos (0, 2.47, -5.8), font_size 40, color `c4baa0`, yaw 0

**Lights (OmniLight3D):**
1. pos (-2, 2.8, -1), color `eac28a`, energy 1.5, range 10
2. pos (4, 2.5, 2), color `8da3b0`, energy 0.7, range 8

**Props (PhysicsProp instances):**
| # | item_name | pos | size | pickup | asset |
|---|-----------|-----|------|--------|-------|
| 1 | Moving box | (4.0+(i%2)*0.6, 0.26, 2.8+(i/2)*0.65) i=0..4 | (0.48,0.5,0.48) | true | cardboardBoxClosed |
| 2 | Old chair | (-2.8, 0.5, 0.8) | (0.55,1.0,0.55) | false | chair |
| 3 | Last clean cup | (-3.6, 0.63, -0.6) | (0.15,0.22,0.15) | true | — |
| 4 | Empty takeaway carton | (1.5, 0.14, 2) | (0.3,0.25,0.24) | true | — |
| 5 | Battered radio | (-3.1, 0.67, -0.6) | (0.25,0.3,0.18) | true | radio |
| 6 | Threadbare pillow | (-4.5, 0.55, 2.4) | (0.5,0.18,0.35) | true | pillow |

**Removed from this room:** Furniture (bed, sofa, coffee table, lamp, fan), dressing/boarded panes, lore plaques (FINAL RENT NOTICE, FREE WINGS FOR LIFE*, PACKING LIST). Replaced by TBD TV/slideshow device.

---

## Room: Casino (`_casino()`)

**Shell:** `_shell(room, 30, 30, 5.2, floor_y=0.5, fancy=true, north_door=true)`

**Floor:** `_floor(room, Color("b3ada0"), marble=true)`

**Tables:** `ChickenCross` at (-5, 0.5, 4) yaw PI; `Cluckjack` at (5, 0.5, 4) yaw PI. Table Counter material_override = `Color("43212b")`. Brass trim boxes on each side.

**Furniture (per side, ±):**
- `tableCoffee` at (±10.5, 0.5, -3), height 0.55, footprint (1.2, 0.55, 0.7)
- `loungeSofa` at (±12.5, 0.5, -3), height 1.15, footprint (2.6, 0.75, 1.0), yaw side*PI/2
- `plantSmall1` at (±12, 0.5, -10), height 1.6
- `lampRoundFloor` at (±12.5, 0.5, 8), height 2.2

**Lights:** at z ∈ {-12, -5, 5, 12}, side ±13.5, pos (±13.5, 3.8, z), color `ffd6a0`, energy 1.7, range 10. Plus brass pillar boxes at (±14.6, 2.95, z).

**Props:**
| # | item_name | pos | size | pickup | asset |
|---|-----------|-----|------|--------|-------|
| 1 | Velvet lounge chair | (±10.5, 1, -1.6) ×2 | (0.75,1,0.75) | false | loungeChair |
| 2 | Complimentary cup | (±10.5, 1.18, -3) ×2 | (0.15,0.22,0.15) | true | — |
| 3 | House chip stack | (±9.9, 1.14, -3) ×2 | (0.16,0.14,0.16) | true | — |
| 4 | Lucky brass paperweight | (10.9, 1.18, -3) | (0.18,0.18,0.18) | true | — (BRASS color) |
| 5 | Room-service crate | (-11, 0.8, 8) | (0.6,0.6,0.6) | false | cardboardBoxClosed |
| 6 | Dealer's stool | (9, 1.1, 6) | (0.55,1.2,0.55) | false | stoolBar |

**Sign boxes:** brass strip structures at z ∈ {-8, 2, 11}; sign face box (9, 2.0, 0.15) at (0, 3.2, 14.75); two shelf structures at (±8, 1.025/1.59, 11).

**Text:**
1. "THE GILDED COOP" — pos (0, 3.5, 14.6), font_size 230, color `f0d39b`, yaw PI
2. "YOUR LUCK. OUR HOUSE." — pos (0, 2.75, 14.6), font_size 80, BRASS, yaw PI
3. "COMPLIMENTARY\nNOTHING ELSE IS" — pos (±8, 2.7, 14.6) ×2, font_size 70, BRASS, yaw PI

**Lore plaques (3 in Casino):**
4. **THE HOUSE RULES** — pos (3.1, 2, -14.82), yaw 0
   - Title: "THE HOUSE RULES"
   - Short: "ONE WALLET. TEN DAYS.\nFive minutes to make quota."
   - Body: "Welcome to the Gilded Coop.\n\nEvery stake leaves the SHARED wallet. Every payout returns to it. Reach the displayed quota before the five-minute bell.\n\nOnce quota is met, gather everyone in the lift and press its button to leave early. The first missed quota spends your only courtesy life and resets the wallet to half its day-start balance. A second miss ends the contract badly. Meet day ten's quota to win."

5. **A WORD FROM THE DEALER** — pos (8.5, 2, -14.82), yaw 0
   - Title: "A WORD FROM THE DEALER"
   - Short: "CLUCKJACK\nHIT for courage. STAND for sense."
   - Body: "Choose a wager on the keypad, then DEAL. Only the bettor may HIT or STAND.\n\nAces are 1 or 11. Face cards are 10. Get closer to 21 than the House without going over. The House stands on all 17s.\n\nGross returns: win 2x, two-card natural 2.5x, tie 1x. Odd-stake half coins round down. The bell or a departing bettor automatically stands the hand.\n\nThe hidden card belongs to the House until the decision is made."

6. **WHY DID YOU CROSS?** — pos (-8.5, 2, -14.82), yaw 0
   - Title: "WHY DID YOU CROSS?"
   - Short: "CHICKEN CROSS\nThe next lane is always tempting."
   - Body: "Set a wager, then CROSS to risk the first lane. CROSS again to continue. CASHOUT banks the current multiplier. A car takes the whole stake.\n\nThe farther the chicken goes, the greater the danger and reward. Anyone may press CROSS or CASHOUT at this table. Agree with your friends before spending their supper.\n\nThe wallet and timer never stop while you argue."

---

## Room: Rest (`_rest()`)

**Shell:** `_shell(room, 12, 12, 3.4, floor_y=0, fancy=false, north_door=false)`

**Floor:** `_floor(room, Color("646d65"))`

**Text:**
1. "COURTESY BREAK" — pos (0, 2.7, -5.8), font_size 100, color `d7d7b8`, yaw 0
2. "The House can wait. The debt cannot." — pos (0, 2.32, -5.8), font_size 36, color `b4bfae`, yaw 0

**Dressing:** box (2.5, 0.07, 0.5) at (0, 3.25, 0), color `d4e3cd`, emission=true

**Light:** pos (0, 2.8, 0), color `cee6d5`, energy 2.0, range 13

**Furniture:**
- `tableCoffee` at (-4, 0, -3), height 0.6, footprint (1.4, 0.6, 0.7)
- `kitchenCoffeeMachine` at (-4, 0.6, -3), height 0.48
- 3 × `chair` at (-4.7, 0, z) for z ∈ {-1.8, 0, 1.8}, height 0.9, footprint (0.5, 0.9, 0.5), yaw PI/2

**Prop:**
- Break-room cup — pos (-3.5, 0.75, -3), size (0.15,0.22,0.15), color `b8c5ad`, pickup=true

**Lore plaque (1 in Rest):**
7. **STAFF MEMO / 04** — pos (0, 1.6, -5.82), yaw 0
   - Title: "STAFF MEMO / 04"
   - Short: "The courtesy is not a refund.\nPlease keep the lift clear."
   - Body: "Guests keep asking where the money went.\n\nAfter a missed quota, the courtesy resets your wallet to HALF what you had at the start of that day. The next quota is still based on that day-start balance. The House offers this only once.\n\nRead the run status board. Gather everyone in the lift and press NEXT DAY when ready.\n\nThe coffee is complimentary. The cups are not collateral."

---

## Props by pickup status

**Pickup-able (pickup=true, kind=GRAB):** Moving box ×5, Last clean cup, Empty takeaway carton, Battered radio, Threadbare pillow, Velvet lounge chair ×2, Complimentary cup ×2, House chip stack ×2, Lucky brass paperweight, Break-room cup. (18 total)

**Non-pickupable / push-only (pickup=false, kind=USE):** Old chair, Room-service crate, Dealer's stool. (3 total)

**Procedural models (no GLB):** cup (cylinder+torus+disc), chip (6 stacked cylinders), everything else = colored box. These become mesh instances in the prop scene.

---

## Assets referenced (Kenney GLBs)

`res://assets/kenney/furniture/`: bedSingle, cardboardBoxClosed, ceilingFan, chair, kitchenCoffeeMachine, lampRoundFloor, loungeChair, loungeSofa, pillow, plantSmall1, radio, stoolBar, tableCoffee. Plus `assets/fonts/ui_font.ttf`.

---

## What is NOT migrated (out of scope or handled elsewhere)

- Elevator cab/interior: built by `elevator.gd` (`_build_cab`) — stays in code.
- Table logic (ChickenCross, Cluckjack): out of scope (brief §11).
- `HUD`, `WorldEnvironment` node itself, `DirectionalLight3D` node: exist in `world.tscn` already.
- `Players`, `MultiplayerSpawner`: exist in `world.tscn` already.

---

## Cut-over checklist (per room)

1. [ ] Build `rooms/<name>.tscn` from this inventory (shell, floor, lights, furniture, props, plaques, text).
2. [ ] Instance into `world.tscn` at the contract name/path.
3. [ ] Verify against this doc: every prop name/position/pickup, every plaque title+short+body, every light position/color/energy/range, every text string.
4. [ ] Remove that room's section from `house_environment.gd`.
5. [ ] Run `run_checks.ps1`; fix regressions.
6. [ ] Commit.

When all three rooms are cut over, delete `house_environment.gd`, its `.uid`, and the `House` node (brief §3.6).

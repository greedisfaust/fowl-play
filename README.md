# Fowl Play

A chicken-themed, first-person co-op casino prototype built in Godot. Friends
share one wallet, chase a five-minute daily quota, and try to survive ten days.
Solo play and LAN sessions with a host plus up to three clients are supported by
the current code. This is a prototype, not a finished release.

## Run the project

1. Install Godot with GDScript support. `project.godot` declares **Godot 4.7**,
   Forward Plus, Windows D3D12, and Jolt physics. Use the team's matching editor;
   compatibility with older versions has not yet been established.
2. Import `dev-fowl-play/project.godot` in Godot, let the initial import finish,
   and press **F6** on `world.tscn` or **F5** for the configured main scene.
   Clean import and smoke checks pass on Godot **4.7.1**.
3. In the apartment, enter a nickname and choose a color. Play solo, or use the
   lobby console to host. Friends enter the host's LAN IPv4 address at the join
   terminal. ENet uses **UDP 7777**; allow the game through the local firewall.
4. Gather all connected players in the elevator and press its button to start.
   In the casino, aim at the bet keypad and table buttons to play Chicken Cross
   or **Cluckjack**, the card table beside it. Select a bet, DEAL, then HIT or
   STAND. [Cluckjack rules and developer checks](docs/CLUCKJACK.md).
5. Meet quota and gather in the casino elevator to finish early, or wait for the
   timer. A day report precedes the rest room or return to the apartment.

There is no matchmaking, Steam integration, voice chat, or NAT traversal. Use the
same revision on every machine. Joining is closed during a run; a host leaving
returns clients to fresh solo runs.

## Controls currently wired

| Action | Input |
| --- | --- |
| Move / look | WASD / mouse |
| Jump | Space |
| Interact with aimed terminal, keypad, or button | E or left mouse |
| Pick up a small prop / push larger furniture | E or left mouse; walk into loose props to push |
| Drop carried object (one slot) | G |
| Charge / throw carried object | Hold / release right mouse (maximum charge: 1.25 s) |
| Read / close lore guides | E or left mouse / E or Escape; wheel or Page Up/Down to scroll |
| Release / recapture mouse | Escape / click |
| Skip day report (host) | Tab |
| Developer teleport to apartment | K or L (unsafe during a run) |

Escape releases the cursor; it does **not** pause the simulation. The GDD's
alternate bindings, teammate combat/carry/throw, and seating are not implemented.
Loose objects support carrying and throwing as described above.

## Project map and documentation

- [Implemented features and GDD differences](docs/STATUS.md)
- [Architecture and adding a table](docs/ARCHITECTURE.md)
- [Prioritized implementation plan](docs/ROADMAP.md)
- [Playability, comparable games, and test protocol](docs/PLAYTESTING.md)
- [Assets and attribution register](docs/ASSETS.md)
- [Cluckjack rules, integration and test commands](docs/CLUCKJACK.md)
- [Room storytelling, physics props and interaction controls](docs/HOUSE_AND_HAND.md)

The supplied **GAMDES1_GDD_Fowl-Play_v3.docx**, dated 30 October 2026, describes
design intent. Code and the status document describe shipped behavior. Record
intentional differences rather than treating every design paragraph as a promise.
The original GDD is not bundled here because it contains team contact details.

`dev-fowl-play/` is the Godot resource root; `docs/` is repository documentation.
Keep generated `.godot/` caches and editor exports out of version control. There
is currently no repository-wide license grant; ask the owners before redistributing
project code or existing art.

# Architecture and contribution guide

All `res://` paths begin in `dev-fowl-play/`. Keep scene-specific scripts next to
their scenes; avoid moving existing UID resources solely for cosmetic cleanup.

| Location | Responsibility |
| --- | --- |
| `autoload/game_state.gd` | Shared wallet, quota/day, timer, extra life, host ledger and report data |
| `autoload/network.gd` | ENet session, roster, names, colors, local settings |
| `autoload/style.gd` | Shared font and text scale |
| `world.gd` / `world.tscn` | Player spawning, room transitions, report lifecycle |
| `player/` | Movement, local camera/input, remote movement interpolation, hands |
| `lobby/` | In-world text entry and lobby controls |
| `elevator/` | Generated cab, occupancy, door state and ride request |
| `tables/` | Shared TableBase, bet panel, PressButton, Screen3D and table subfolders |
| `ui/` | HUD, fade, day report and wallet chart |

## Table request lifecycle

The local ray hits a `PressButton`. Its signal calls `send_action()` or
`request_play.rpc_id(1, seen_bet)`. The host validates sender, phase, bet, wallet,
and round ownership before spending anything. `locked_bet` is the committed
stake; a later wallet change must never alter it. The table owns the rules and
random draws. Only public presentation events go to clients via `emit_event`.
`finish_round(payout)` returns the **gross payout including stake**, logs once,
and unlocks the table. A loss pays 0, a push pays the stake, an even-money win
pays twice the stake. Never deduct the stake twice or add only net profit.

The existing code has validation gaps listed in [STATUS.md](STATUS.md); this
description is the contract to enforce as new tables are integrated.

## Adding a minigame

1. Add `tables/<name>/` with an inherited `table_base.tscn` scene and a script
   extending `TableBase`. Preserve `BetPanel` and `Buttons/PlayButton`, or set
   `uses_play_button=false` and supply a replacement start action.
2. Set `display_name` and `only_bettor_can_act` explicitly. Override
   `_on_round_start`, `_on_player_action`, `_on_event`, and `_on_table_ready`.
3. Keep rules in a separate RefCounted script where practical, with deterministic
   deck injection for tests. Never trust client-provided cards, totals or payouts.
4. Reject invalid actions and invalid transitions. Broadcast only the visible
   hand; keep undealt cards and the dealer hole card on the host until reveal.
5. Resolve through `finish_round` exactly once. Handle timeout, bettor disconnect,
   run reset, and a host leaving. Clear pending visual work before the next round.
6. Instance the table under `World/Casino`, with consistent node paths on peers.
   Leave walking space around its keypad and buttons and keep signage readable.
7. Add rule and integration checks and a manual two-instance smoke test. Update
   status, controls, asset credits and the roadmap with actual behavior.

## Validation workflow

Use a clean Godot import, then headless editor validation and a main-scene smoke
run. Run targeted deterministic tests for card rules/economy. For multiplayer,
run two copies at the same revision, host one, join `127.0.0.1` from the other,
then repeat on LAN with four players. Headless rules alone cannot verify camera
readability, interaction reach, feedback, performance or fun.

Use small branches and PRs. Documentation lands first; feature branches may be
stacked on it, then retargeted to `main` after the documentation PR merges. List
actual checks and known gaps in each PR. Do not bundle generated caches, local
settings, downloaded archives or unrelated scene reformatting.

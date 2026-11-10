# Implementation audit

Baseline: `a358ecd`, audited 10 November 2026 against GDD v3. **Implemented** here
means present in source; multiplayer reliability and player enjoyment still need
the repeatable checks in [PLAYTESTING.md](PLAYTESTING.md).

| Area | Current implementation / evidence | Remaining work |
| --- | --- | --- |
| First-person player | `player/player.gd`, CharacterBody3D movement, jump, mouse look, ray interactions, animated hands and nameplates | Rebinding, sensitivity settings, seating, physical teammate interactions |
| LAN lobby | `autoload/network.gd`, ENet UDP 7777, four slots, unique nicknames/colors, locally saved settings, create/join/leave terminals | Join timeout UX, hostile-input validation, latency/disconnect testing; no online discovery |
| Replication | `world.tscn` MultiplayerSpawner; owner-authoritative movement with remote interpolation; host-owned wallet/table results | Movement is not host-authoritative as proposed by GDD; distance checks and rate limits remain |
| Run loop | `autoload/game_state.gd`, REST/DAY, 300-second days, ten-day win, one failed-day extra life | Balance validation, complete run soak tests, full HUD day/life indicators |
| Economy | Shared starting 1,000; first quota 1,250; later quota derived from previous wallet and multiplier array; extra-life resets to half day-start wallet | Economy simulation across policies and player counts; approved tuning sheet |
| Bets | `tables/table_base.gd`, host deducts stake, wallet-derived min/max, presets, one active round per table | Reject out-of-phase starts, spoofed round ownership, malformed RPC inputs |
| Chicken Cross | 12 lanes, host rolls busts, escalating payout, cash-out, basic hop/crash effects | Odds signage, sound, tuning. Anyone may push/cash out (`only_bettor_can_act=false`), unlike GDD exclusive seating |
| Blackjack | Specified in GDD, no scene or rules yet | Next feature: **Cluckjack**, see roadmap |
| Other tables | No Eggsweeper, roulette, or poker implementation | Add independently; rotation requires enough working tables |
| Elevator transitions | `elevator/elevator.gd`, all connected peers aboard, quota gate, fades, forced timeout departure | Missing-player recovery, level polish; distinct apartment/rest/casino areas differ from GDD one room |
| Reports | `ui/day_report.gd`, ledger, wallet chart, biggest wins/losses, player contributions, host skip | Usability/readability and synchronization testing |
| Social slapstick | Hands reach toward interacted objects | No damage/hit cost, stun, carry-lock, drop, or throw |
| Watched / rotation | Absent | Blessed/Cursed assignment, effects and anti-repeat rules; four-of-five table rotation |
| Presentation | Primitive geometry, runtime screens, shared font, text announcements | Chicken character art, audio, house dialogue, environmental changes, feedback |
| Accessibility / release | Cursor release only; no export presets or CI tests | Pause/settings UX, alternate inputs, contrast/text controls, captions, export checklist |

## Known technical risks

- Clean import using installed Godot 4.7.1 reports type-inference parse errors in
  `player/player.gd:23`, `world.gd:181-182`, and `lobby/color_board.gd:12` where
  values come from autoloads. Startup is blocked until explicit types are added.
  The editor process can return exit code 0 despite these script errors; inspect
  its output rather than relying on the exit code alone.
- `TableBase.start_round` is exposed as `any_peer` and accepts `who`; derive peer
  identity at the RPC boundary instead. Start gating must consider both phase
  and whether the day is running. Existing actions must settle after timeout.
- `world.gd` waits up to ten seconds then forfeits unfinished rounds. New games
  must define what a timeout means and cannot pay again after forced settlement.
- Table state is not cleared by `GameState.reset_run()`. Reset/leave must not
  carry an unfinished hand or delayed payout into a new run.
- `_full_state` does not include phase or ledger. Joining is blocked in runs;
  reconnect or join-in-progress needs a deliberate complete snapshot design.
- K/L developer teleport changes host phase without the normal transition. Keep
  it out of playtests and remove or debug-gate it before distributing builds.
- Existing font provenance is unknown. A `.ttf` being in Git does not establish
  redistribution rights. See [asset register](ASSETS.md).

No playtest results or performance measurements have been collected by this audit.

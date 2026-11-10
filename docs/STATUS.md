# Implementation audit

Baseline: `a358ecd`, audited 10 November 2026 against GDD v3; updated for the
Cluckjack and House/hand features. **Implemented** here
means present in source; multiplayer reliability and player enjoyment still need
the repeatable checks in [PLAYTESTING.md](PLAYTESTING.md).

| Area | Current implementation / evidence | Remaining work |
| --- | --- | --- |
| First-person player | `player/player.gd`, movement, jump, look, ray interactions, hands/nameplates; crosshair, focus glow, prompts, single-slot props and charged throw | Rebinding, sensitivity settings, seating, physical teammate interactions |
| LAN lobby | `autoload/network.gd`, ENet UDP 7777, four slots, unique nicknames/colors, locally saved settings, create/join/leave terminals | Join timeout UX, hostile-input validation, latency/disconnect testing; no online discovery |
| Replication | `world.tscn` MultiplayerSpawner; owner-authoritative movement with remote interpolation; host-owned wallet/table results | Movement is not host-authoritative as proposed by GDD; distance checks and rate limits remain |
| Run loop | `autoload/game_state.gd`, REST/DAY, 300-second days, ten-day win, one failed-day extra life; HUD day/life indicators | Balance validation and complete-run soak tests |
| Economy | Shared starting 1,000; first quota 1,250; later quota derived from previous wallet and multiplier array; extra-life resets to half day-start wallet | Economy simulation across policies and player counts; approved tuning sheet |
| Bets | `tables/table_base.gd`, host deducts stake, wallet-derived min/max, presets, one active round per table; active-day gating and sender-derived ownership | Interaction distance checks and rate limits |
| Chicken Cross | 12 lanes, host rolls busts, escalating payout, cash-out, basic hop/crash effects | Odds signage, sound, tuning. Anyone may push/cash out (`only_bettor_can_act=false`), unlike GDD exclusive seating |
| Blackjack | **Cluckjack**: 52-card host deck, Hit/Stand, soft aces, naturals, dealer 17, public cards/totals, gross payouts and report integration | Four-player human LAN/playability pass; no advanced blackjack options |
| Other tables | No Eggsweeper, roulette, or poker implementation | Add independently; rotation requires enough working tables |
| Elevator transitions | `elevator/elevator.gd`, all connected peers aboard, quota gate, fades, forced timeout departure | Missing-player recovery, level polish; distinct apartment/rest/casino areas differ from GDD one room |
| Reports | `ui/day_report.gd`, ledger, wallet chart, biggest wins/losses, player contributions, host skip | Usability/readability and synchronization testing |
| Social slapstick | Hands reach toward interacted objects; loose objects support push/carry/throw | No teammate damage/hit cost, stun, carry-lock, drop, or throw |
| Watched / rotation | Absent | Blessed/Cursed assignment, effects and anti-repeat rules; four-of-five table rotation |
| Presentation | Enclosed apartment/casino/rest rooms, windows/sky/roof, licensed Kenney furniture, distressed apartment story, fancy casino aisle, seven lore guides, focus feedback, day/life HUD | Chicken character art, audio, voiced House dialogue, reactive environmental changes |
| Physics props | Host rigid bodies, 15 Hz client interpolation, one-slot pickup, push, host-timed charged throw, drop/disconnect/transition/reset recovery | Four-player latency and clutter playtest; no prop damage/consumables |
| Accessibility / release | Crosshair, text prompts, named inventory feedback, scrollable lore and cursor release; no export presets or CI tests | Pause/settings UX, alternate inputs, contrast/text controls, captions, export checklist |

## Known technical risks

- Baseline Godot 4.7.1 type-inference parse errors in player, world and color
  board scripts are fixed. The test runner checks error output as well as exit
  codes because Godot can report script errors while returning zero.
- `TableBase.start_round` is now host-local, with peer identity derived at the
  request boundary. New rounds require an active running day. Proximity and RPC
  rate limits remain unimplemented.
- `world.gd` asks tables to settle at departure, then waits up to ten seconds and
  forfeits any remaining rounds. Cluckjack auto-stands immediately; Chicken
  Cross retains its forfeit policy. Delayed Cross payouts are invalidated on reset.
- Session reset now clears table state and Cluckjack hands. New table types must
  implement their own reset/settlement hooks and avoid delayed stale mutations.
- `_full_state` does not include phase or ledger. Joining is blocked in runs;
  reconnect or join-in-progress needs a deliberate complete snapshot design.
- K/L developer teleport changes host phase without the normal transition. Keep
  it out of playtests and remove or debug-gate it before distributing builds.
- Existing font provenance is unknown. A `.ttf` being in Git does not establish
  redistribution rights. See [asset register](ASSETS.md).

Validation: clean Godot 4.7.1 import, headless main-scene smoke run, deterministic
rules/economy/lifecycle suite, real two-process ENet loopback test and rendered
table capture; room/prop tests and a full-world ENet prop test. See
[CLUCKJACK.md](CLUCKJACK.md) and [HOUSE_AND_HAND.md](HOUSE_AND_HAND.md) for commands and limits. No human
playtest results or performance measurements have been collected.

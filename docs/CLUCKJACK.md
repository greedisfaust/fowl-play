# Cluckjack

Cluckjack is the chicken-named blackjack table at casino-local `(5, 0.5, 4)`,
beside Chicken Cross. Aim at the shared keypad, choose a wager, then press DEAL
with E or left click. Only the player who deals can HIT or STAND. Walking away
does not transfer ownership; return to finish, or the day-end policy settles it.
Other players see the hand and can discuss the risk while their shared wallet
remains visible in the HUD.

## Rules and feedback

- Fresh host-shuffled 52-card deck every hand, drawn without replacement.
- Aces count as 1 or 11, face cards as 10. The best non-busting total wins.
- Dealer's second card and total stay hidden during the player's turn. Dealer
  draws below 17 and stands on every 17, including soft 17.
- HIT at 21 automatically stands. A bust ends immediately. Naturals resolve at
  deal: both natural hands push; dealer natural beats any non-natural hand.
- Gross returns include the original stake: normal win 2x, two-card natural
  2.5x, push 1x, loss/bust 0. Half-coin natural returns round down (101 returns
  252). No split, double, insurance, surrender, or side bets.
- The board shows cards, totals, active bettor, committed stake, outcome and
  gross return. C/D/H/S mean clubs/diamonds/hearts/spades; color is supplemental.
- Time expiry, early elevator departure, or bettor disconnect automatically
  stands and resolves before the report. Disconnect keeps the original bettor's
  name/color in the host ledger. Leaving the session resets all local table state.

## Implementation

`tables/cluckjack/cluckjack_rules.gd` is a RefCounted host hand model, independent
of UI/wallet. `cluckjack.gd` integrates TableBase, public snapshots and procedural
card faces. Clients receive visible cards and an action revision, never the
undealt deck or hidden card. Duplicate/stale Hit/Stand requests are ignored by
checking that revision. Only the host credits gross payouts and appends ledger
entries. There is no seeded deck or client-supplied draw in production.

Shared integration changes reject new hands outside a running day, derive bettor
identity at the RPC boundary, validate keypad digits, reset tables on session
reset, and invalidate delayed Chicken Cross payouts. Four existing explicit-type
fixes allow a clean Godot 4.7.1 import. This does not add anti-cheat movement,
interaction-distance checks, rate limits or join-in-progress support.

## Reproduce checks

From repository root in PowerShell, with the console build of Godot 4.7.1:

```powershell
./dev-fowl-play/tests/run_checks.ps1 -GodotPath 'C:/Program Files/Godot/Godot_v4.7.1-stable_mono_win64_console.exe'
```

This imports, runs deterministic rules/economy/lifecycle checks plus 2,000 shuffled
deck-conservation cases, starts the main scene for 120 frames, and runs two real
ENet processes on loopback UDP **17777**. The network test verifies a client-owned
hand, spectator rejection, duplicate Stand, hidden-card reveal, shared balance and
one host ledger entry. It uses the same inherited scene/RPC code with a fixed
host deck from `tests/cluckjack_fixture.gd`. Test scenes are not the main scene.
The runner fails on script errors even if Godot returns exit code zero.

Recorded validation on 10 November 2026: Godot 4.7.1 on Windows, **2,042 checks,
zero failures**, both ENet processes passed, and the main-scene smoke run and
editor import produced no script errors. Chicken Cross cash-out and cancellation
of a pending payout on reset are included. A 1280x900 Compatibility-renderer
capture was inspected on an RTX 3050 Ti; this is not a frame-rate benchmark.

Optional rendered QA (requires a display; do not use `--headless`):

```powershell
& 'C:/Program Files/Godot/Godot_v4.7.1-stable_mono_win64_console.exe' --path dev-fowl-play --rendering-method gl_compatibility --resolution 1280x900 res://tests/capture_cluckjack.tscn -- --capture=C:/absolute/path/cluckjack.png
```

The capture scene exits after saving a fixed hand. It tests the board layout,
not real player input or fun. Actual four-player LAN sessions, full ten-day
runs, normal-camera reach/readability, and target-PC performance remain manual
acceptance work in [PLAYTESTING.md](PLAYTESTING.md).

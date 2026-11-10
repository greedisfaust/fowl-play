# Delivery roadmap

Order reflects prototype risk, not a claim that the GDD is final. Complete one
small playable increment at a time and update [STATUS.md](STATUS.md).

| Priority | Deliverable | How to implement | Acceptance |
| --- | --- | --- | --- |
| Delivered; human LAN pass pending | **Cluckjack** table | TableBase scene with isolated 52-card model, host draws, Hit/Stand, public hands/totals, gross payout and ledger | Automated rules/lifecycle and ENet loopback pass; complete human LAN checklist next |
| Delivered core; hardening remains | Lifecycle and RPC integrity | Host-local start helper, sender/phase/bet checks, single settlement, table reset and delayed-payout invalidation | Automated invalid-request and reset checks pass; add proximity/rate limits later |
| P1 | Social intervention slice | Host-validate nearby hit, charge quota-based hit cost, add timed stun; then carry/drop/throw states with camera look retained | Two peers can stop/release a gambler; disconnect releases carried player; no permanent input lock |
| P1 | Playable economy | Simulate conservative/aggressive/random table policies, then run timed LAN sessions | Record success distribution, round durations, reasons for failures and changes; no unmeasured difficulty claims |
| Delivered feedback/guides; settings pending | Readable onboarding/settings | Aim prompts, focus glow, crosshair, lore/table rules, inventory/charge UI and day/life HUD are present; add disabled-action clarity, sensitivity/rebind and text scale next | New players place and resolve a bet without coaching; text and symbols work without color |
| P2 | Remaining minigames | Eggsweeper first using host-only nest map; roulette and simplified poker follow as isolated rules and scenes | Correct distributions/payouts, public-only snapshots, common lifecycle suite |
| P2 | Rotation and Watched | Four of five complete tables; host draws daily roster/effects with no-repeat history | Every connected player has a table; status announces and clears consistently |
| P2 | Presentation and release | Licensed chicken art/audio, house text/captions, lighting, debug-key gating, exports and CI | Four-player complete run, target hardware frame-time capture, clean-machine build |

## Cluckjack design decision

Use the chicken-derived name **Cluckjack** on the table and in reports. Keep
blackjack terminology in developer docs for discoverability. Follow GDD section
6.4: fresh shuffled 52-card deck each hand, A=1/11, faces=10, dealer stands on all
17s, win=2x gross, two-card natural=2.5x gross, tie=1x, loss=0. Two naturals push;
dealer natural beats ordinary 21. Only the bettor chooses Hit or Stand; friends
can watch. No split, double, insurance, surrender or side bets in this slice.
Integer wallets require a defined half-coin policy: round gross natural payouts
down for odd stakes and disclose this in table rules. Auto-stand at 21; timeout
or bettor disconnect stands and settles the hand before the day report.

This deliberately adds a familiar decision game alongside Chicken Cross. Its
standard odds may be less generous than the GDD's early Cross stops. Tune the
quota/rotation from measurements instead of silently rigging the deck.

## Inputs needed from the team

- Confirm the intended Godot version and minimum target PC/GPU.
- Supply the bundled font's source/license or approve replacing it before release.
- Schedule at least three four-player LAN groups for the first playability pass.
- Approve economy changes and any later revision of the chicken theme, table
  ownership rules, accessibility scope, and original-code license.

These are release/planning dependencies; they do not block the next table slice.

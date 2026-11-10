# Playability and success criteria

## Comparable games

Primary store descriptions checked 10 November 2026. These are design references,
not evidence that Fowl Play is fun or will reach comparable sales. No assets,
branding, dialogue or code from these games should be copied.

| Reference | Relevant published premise | Fowl Play hypothesis to test |
| --- | --- | --- |
| [Gamble With Your Friends](https://store.steampowered.com/app/3892270/Gamble_With_Your_Friends/) | Shared bank/debt, short daily quota, co-op casino | Shared spending should create visible negotiations; check players understand who spent what |
| [Lethal Company](https://store.steampowered.com/app/1966720/Lethal_Company/) | Co-op scavenging and selling scrap to a company | Shared stakes and a return ritual can structure the session; test whether elevator/report pacing supports replay |
| [R.E.P.O.](https://store.steampowered.com/app/3241660/REPO/) | Co-op retrieval of physics-based valuables | Physical interactions can generate memorable coordination errors; test hit/carry only after a stable social slice exists |

Our proposed distinction is chicken casino comedy with direct teammate
intervention in a compact room. Current code provides shared risk and a report,
but cannot yet establish the physical-comedy part. Another game's review score
does not verify our playability. Compare observed behavior, not raw sales totals.

## First playtest protocol

Use three groups of four (12 people), including at least one newcomer per group.
Use the same build and record revision, hardware, player count, network type,
session length and facilitator help. Run one uncoached first day, one explained
run, then offer a voluntary replay. Collect individual feedback before group
discussion. These are **proposed prototype gates, not measured results**:

| Measure | Initial gate | Capture method |
| --- | --- | --- |
| First interaction | 10/12 place and resolve a bet within 90 seconds without coaching | Observer timestamps from spawn; note confusion |
| Rule clarity | 10/12 explain shared wallet, quota, and Cluckjack Hit/Stand | Three short post-day questions |
| Social engagement | Each group has at least 3 spontaneous risk discussions per day | Observer event tally; don't count prompted conversation |
| Session stability | 0 crashes, stuck transitions, duplicated payouts or wallet divergences across all groups | Host/client logs and wallet snapshots after each hand |
| Desire to replay | At least 8/12 choose another day/run when offered | Individual yes/no and reason; report numerator and denominator |
| Opening difficulty | First-day pass in 2/3 groups after rules explanation | Day ledger; small sample is directional only |
| Table pacing | Median Cluckjack hand under 30 seconds; no unexplained idle lock beyond 10 seconds | Deal-to-result timestamps and observer notes |
| Performance | Aim for 60 FPS on agreed minimum hardware | Record frame-time percentiles with four players; target PC still to be supplied |

Keep a CSV with session_id, revision, player_count, day, duration_s, rounds,
start_wallet, end_wallet, quota, outcome, desync_count, help_count, replay_votes,
and notes. Use anonymized IDs. The host ledger already records bets, gross
payouts, player names and timing; export anonymized data only with participant
consent. It is not currently an automated telemetry service.

After this pilot, increase sample size before setting retention or difficulty
targets. Separate game-rule faults from usability failures and balance feedback.
Change one major variable per iteration and repeat the same protocol.

## Regression checklist

- Clean import and startup; local movement and interaction; host/join with
  `127.0.0.1`, then LAN; unique names/colors; failed join and host departure.
- All connected players required for elevator departure; quota lock; timer expiry;
  extra life exactly once; second failure; day-ten win; host report skip.
- Min/max/zero/unaffordable wagers, simultaneous table starts, insufficient
  balance after another table spends, duplicate Play/Hit/Stand requests.
- Cluckjack player/dealer natural, both naturals, soft/multiple aces, busts,
  ordinary ties, dealer stands at soft 17; hidden dealer card stays hidden until
  resolution; spectators cannot act; report payout matches wallet delta.
- Timeout during hand, bettor disconnect, leave-to-solo and fresh run; no hand
  or payout survives reset. Chicken Cross still hops/cashes out.
- Read signs/buttons from normal player height; walk around both tables without
  trapping players; verify without sound and without relying on red/green alone.

Automate deterministic rules and transaction invariants; use humans for fun,
readability and physical interaction. Keep a dated result log with pass/fail,
reproduction steps and actual measurements rather than ticking unrun checks.

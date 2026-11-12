# Fowl Play — Foundation Overhaul
### Interactables · Carry/Throw · Physics · Player States (knockdown / ragdoll)

> Paste everything below into Claude Code. Delete the line marked `CHECKPOINT` in section 5 if you want it to run straight through without stopping for review.

---

## 1. Mission

The code in `dev-fowl-play/` has grown by patching, and its systems now contradict each other. The result is a steady stream of bugs where one script assumes something another script no longer guarantees. Your job is **not to patch the next bug**. Your job is to **replace the overlapping systems with one clean, well-understood foundation** that everything else inherits from or plugs into, so that new features cannot contradict old ones.

Work in this mindset for every decision:

> "What is the single baseline that every current and future thing of this kind will build on? If I add the 20th prop, the 5th table button, or ragdoll a player, do I touch one place or six?"

If the answer is six, the design is not finished yet.

## 2. Authority you have been given

You have **full control** over the codebase for this task. Specifically, you may:

- Rewrite, split, merge, rename, move or **delete** any script, scene, test or doc.
- Add new GDScript files, scenes, components, resources and base classes whenever they make the structure clearer.
- Remove a whole mechanism and replace it with one unified class, even if that touches many files.
- Re-implement any behavior, as long as the behaviors listed in section 7 still work afterwards (you may re-tune them, but call out every deliberate change).
- Rewrite `tests/` to match the new structure, as long as coverage is not reduced.

The guardrails are in section 8. Outside those, **do not hold back out of caution about the existing code**. Its existence is not a reason to keep it.

The one requirement that comes with this freedom: **understand the current flow before changing it** (Phase 0), and leave the result **understandable by a teammate who has never seen it**.

## 3. What is wrong right now (verify each point against the live code)

Some of these were observed in earlier versions of the code. Treat them as leads, not facts. Confirm each one, then decide where it gets fixed in the new design.

**Structural contradictions**
- `Interactable` is a `class_name` contract, but it is only a duck-typed convention (`has_method("interact")`, `Interactable.can(node)`). `PhysicsProp` (RigidBody3D), `PressButton`, `TextTerminal`, `LorePlaque` (StaticBody3D), elevator and bet-panel buttons cannot share a base class because GDScript has single inheritance. Prompt and highlight logic still branches on concrete types in places.
- `Carryable` is also duck-typed. Carrying **items** (PhysicsProp RPCs: `request_use`, `request_charge`, `request_release`, `_sync_holder`) and carrying **players** (Player RPCs: `_pickup_request`, `_launch_carried_player`, `take_punch`) are two parallel implementations of the same idea.
- Player state is spread across `PlayerState`, `Carrier`, `Combat`, legacy "test-compat" vars at the bottom of `player.gd`, `ragdolled_until`, `_launch_until`, and `input_locked` hacks that zero launch velocity on frame 1.
- `house_environment.gd` builds props through `_prop()`, `_furniture()` and `_asset()`, each duplicating collision-shape and model-placement code, and bypasses any shared template. The file also mixes materials, room shells, furniture, notices, props and lore in one place.
- One input action (`punch_charge`) means both "charge a punch" and "charge a throw". E and left mouse both run the same interact path, so a cup beside a keypad is picked up when you meant to press a button.
- Held items are found by scanning the `physics_props` group every frame (`Prop.held_by`). Players are found by walking raycasts up to a node whose name matches `^\d+$`.

**Known defects (verify, then make sure the new design makes them impossible)**
- A carrier who disconnects leaves the carried player stuck forever (`_carrier_id` never cleared).
- Throw/RPC targeting for carried players (`_carried_player_id` vs `multiplayer.get_unique_id()`) can mismatch.
- Pressing Escape while charging a throw **drops** the item instead of cancelling the charge. A lost mouse-release (cursor released, input locked, typing at a terminal) leaves the host still charging, so the next tap becomes a full-power throw. The meter runs on the client clock while the host decides power.
- Throw direction and origin come from the host's interpolated copy of the thrower's head, so client throws can leave off-aim.
- The sender never sees their own punch swing (`_net_jab` / `_net_punch` are `call_remote`).
- Physics feel: `linear_damp = 0.8` makes props floaty, player gravity is 20 while props use the default 9.8, and there is no `PhysicsMaterial`. Throws set velocity in the same frame the body is unfrozen.
- Every prop sends a 15 Hz transform snapshot forever, even when asleep.
- Pickup reach is validated against the host's lagged copy of the client's position.

## 4. Design requirements (the foundation)

Satisfy these. How you do it is your call, but record the decision and the reason in `docs/OVERHAUL_LOG.md`.

**R1 — One interaction model.**
Everything the player can aim at and act on goes through **one mechanism**: one lookup (collider → interactable), one source of prompt text, one highlight rule, one enabled/disabled-with-reason check. At minimum there are two verbs, **USE** (buttons, keypads, terminals, plaques, elevator) and **GRAB** (carryable items, downed/carried players). Props, buttons, terminals, plaques, the elevator button, bet-panel keys and knocked-down players must all conform. No more `if target is PressButton / elif TextTerminal` chains.
*Hint:* because GDScript is single-inheritance, a small **component** (a child `Node` such as an `Interactable` component with `prompt`, `kind`, `enabled`, `can_interact(player)`, `interacted` signal, plus a static `find(collider)`) usually beats a base class. Choose what actually works, and justify it.

**R2 — One carry model for items and players.**
One holder↔held relationship, **host-authoritative**, one pickup / drop / throw path, used for both props and players. Ideally one registry (for example a host-side manager) owns "who holds what", which also makes cleanup trivial. Cleanup is guaranteed, with no ad-hoc code, in every one of these cases: carrier disconnects, carried disconnects, run reset, elevator transition, teleport, knockdown ending, carrier knocked down, host leaves. Charge rules: the host times the charge, cancelling a charge **never** drops the item, the client sends aim with the release and the host validates and clamps it, and the host resets charge state on every exit path.

**R3 — One physical-body foundation (players will be ragdolls).**
Props and ragdolling/thrown players must share one contract for: who simulates it (authority, defined explicitly), applying impulses or launches, impact events (the wall-slam VFX hangs off this), sleep, replication of state, and the physics tuning constants (damping, gravity scale, friction/bounce, throw speeds). Put all tuning numbers in one place instead of magic numbers across files. For players you must **decide and document the authority model** for knockdown / carried / thrown / ragdoll (who simulates, how the owner and host stay in sync, how a client is prevented from fabricating a launch). It has to hold up for 4 players on LAN latency. You do not have to build full skeletal ragdoll visuals now. You **do** have to make sure the foundation will not need to be torn up when they arrive.

**R4 — One player state machine.**
`PlayerState` is the single answer to "what can this player do right now?". Input, interact, punch, pickup, movement lock, hover/glow and hands poses must all query it. Document the legal-transition matrix. Fold `ragdolled_until`, `_launch_until` and the `input_locked` hacks into proper states or state data. **Delete the legacy compat vars in `player.gd`** and update the tests instead.

**R5 — One prop template, data-driven.**
Props are declared as data and built by one template or factory (collision, model placement, mass, pickup rules, home transform, name). `house_environment.gd` should shrink to layout and declarations. Split it if that makes it clearer. Node names and paths must stay **deterministic and identical on every peer** (RPC paths depend on it).

**R6 — One input map with no overloaded actions.**
Each action has exactly one meaning. Separate USE, GRAB, DROP, THROW (charge), PUNCH and PARRY. Context resolution (what a press does depending on state and target) lives in **one place**. Keep default bindings as close to the current ones as makes sense. Produce a final input table, flag it in your report as a design decision to review, and update README and docs.

**R7 — Clean extension points, not new visuals.**
- *Hands:* the visual model in `player/hands.gd` has recent hand-tuned work (some uncommitted). **Do not change how the hands look, and do not revert that file.** You may add or adjust API hooks only (for example "holding an item", "grab-hover vs point-hover"). Keep the existing contract: `set_hover`, `update_hover_point`, `reach`, `set_color`, `add_sway`, `set_speed`.
- *UI:* the charge meter and overlay will be redesigned later. For now the overlay must read from clean state (carrier / focus), not scattered variables.

**R8 — Networking hygiene.**
Host-authoritative. Every `any_peer` RPC validates `get_remote_sender_id()` and phase/state. Keep RPCs in as few places as possible (prefer the registry/manager over RPCs scattered across props, players and components), use consistent naming and explicit modes, and add basic rate limiting to any new RPC. Only replicate what changed (stop sending snapshots for sleeping bodies). State the late-join behavior explicitly even though join-in-progress is unsupported.

**R9 — Readable by a stranger.**
- Every script starts with a `##` header saying what it is and what it owns.
- One responsibility per script. `player.gd` stays a thin coordinator.
- No dead code, no commented-out code, no leftover "legacy" shims.
- Static typing everywhere. Avoid `:=` inference traps (Godot 4.7.1 has already produced parse errors from them).
- No abstraction without **at least two real consumers today**. Do not build a framework for hypothetical needs.
- Constants named with units (`_SECONDS`, `_MPS`) where it helps.

**R10 — Prove it.**
Update and extend `tests/` (including `test_house.gd`, which references legacy APIs: `_handle_carry_input`, `Prop.held_by`, `Prop.throw_speed`, `drop_for_transition`, `reset_prop`, `_charge_started`, `holder_id`). You may change those APIs, but every check must be **ported to the new API**, not deleted. Add checks for: interactable targeting and enabled/disabled reasons, item **and** player carry/drop/throw through the same path, cancel-charge-keeps-item, host charge reset on every exit path, carrier/carried disconnect, reset/elevator/teleport cleanup, state-machine legal/illegal transitions, and double pickup.

## 5. Phases (each phase must leave the game launching and playable)

**Phase 0 — Understand (read-only; no code edits).**
Trace the real flow end to end: input → focus/hover → interact → RPC → host validation → replication → visuals, for (a) props, (b) buttons/terminals/plaques/elevator, (c) carrying items, (d) carrying and throwing players, (e) punch → knockdown → ragdoll → recovery. Use grep to find every reader and writer of each piece of state. Write `docs/OVERHAUL_LOG.md` containing:
1. the system map;
2. a **contradiction ledger** (each contradiction → where it lives → how the new design removes it);
3. the proposed architecture (text diagram: components, owners, authority, RPC surface);
4. a migration table (file → keep / merge / delete / new);
5. the risks and the decisions you need the user to review.

> **CHECKPOINT (delete this line to run straight through):** stop here and show the user the log. Continue only after they approve or adjust.

**Phase 1 — Safety baseline.**
`git status` shows uncommitted work (`player/carrier.gd`, `player/hands.gd`, `player/player.gd`, `player/player_state.gd`, `tests/test_house.gd`, `world.gd`) and an untracked `docs/INTERACTION.md`. Commit it as a labeled baseline on the current branch (`features/physics-overhaul-and-mechanics`) so nothing is lost and the overhaul diff is reviewable. Never use destructive git commands (`reset --hard`, `checkout --`, force push, `clean`). Do not push.

**Phase 2 — Build the foundation.** Implement R1–R5 core pieces (interaction component, carry registry, physical-body contract, prop template, state-machine cleanup) with unit-level checks as you go.

**Phase 3 — Migrate every consumer.** Props (via the template), buttons / keypads / terminals / plaques / elevator / bet panel (via the interaction model), downed and carried players (via the carry + physical-body model), focus, overlay, hands hooks, world transitions.

**Phase 4 — Delete and unify.** Remove the old mechanisms, duplicated builders, legacy vars, overloaded input action and scanning helpers. Re-grep for stragglers. Shrink `player.gd` and `house_environment.gd`.

**Phase 5 — Harden.** Walk the known-defects list in section 3 and prove each is impossible or fixed. Build and check the **cleanup matrix**: every holding or state event (disconnect of either party, reset, elevator, teleport, knockdown end, host leaves) against every thing that can be held or carried.

**Phase 6 — Document and report.** See section 9.

## 6. Method: think twice

- **Before you delete or merge anything:** list every consumer (grep), say what replaces it, and confirm nothing depends on its side effects.
- **After each change:** grep for stale references, then re-read your own diff as if reviewing a stranger's PR.
- **When two scripts disagree** about a rule, decide which one owns it, make everyone else ask that owner, and record it in the ledger.
- **Prefer replacing over patching.** If a fix needs a flag to work around another flag, the structure is wrong.
- **When in doubt,** choose the simplest design that satisfies R1–R10, write down why, and move on. Do not stop to ask unless an action is destructive or irreversible.

## 7. Behaviors that must still work afterwards

You may re-implement and re-tune. Report every deliberate change.

- Punch: charge punch (hold; knocks the target down for about 2.5 s) and a light jab (quick tap, brief flinch, no knockdown).
- Parry: press, 1.5 s grace window, then cooldown. Parrying a charged punch knocks the attacker down.
- Shakedown: charged-punch hit costs 5% of the wallet, **day phase only**, routed through `GameState._set_wallet.rpc()`.
- Carry and throw items and downed players: pick up, drop, hold to charge, release to throw. Carried players stay down until thrown. Carried bodies cannot clip through walls. The carrier keeps movement control. Thrown players keep their launch velocity through flight.
- USE is blocked while carrying (or an equivalent rule you document).
- Hover/glow on a player only when stunned or carried.
- Wall-slam feedback (notice, camera and hand shake scaled by impact speed).
- Props: pickup range and line-of-sight checks, one-slot carry, push, drop on elevator transition, return home when out of bounds, reset on run reset.
- Everything else in the game: lobby, elevator, economy, tables, reports.

## 8. Guardrails (what you must not change)

- **Out of scope:** economy and quota numbers, table rules (Chicken Cross, Cluckjack), the day-report, lobby and elevator logic (except where they must call the new carry/state APIs), assets and licenses, the GDD.
- **Hands:** keep the look and the public API (R7). Do not revert uncommitted user changes.
- **No new gameplay features.** Only restructure, fix, and expose clean hooks.
- **Godot hygiene:** moving a script means moving its `.uid` file with it. Fix every `preload`, `ext_resource` path and autoload reference. Node names must be identical across peers.
- **This machine:** Windows 11, Git Bash (use forward slashes). The Godot console build is **not installed here**, so you cannot run the test suite. Reason carefully about every change, mark what is **unverified**, and give the user the exact commands to run:
  `./dev-fowl-play/tests/run_checks.ps1 -GodotPath '<path to Godot_v4.7.1 console exe>'`

## 9. Deliverables

1. The refactor itself, committed in clear phase-sized commits on the current branch (do not push).
2. `docs/OVERHAUL_LOG.md`: system map, contradiction ledger (with resolutions), decision records, what was deleted and why.
3. `docs/INTERACTION.md` finalized: the contracts, the authority/ownership table, the player state-transition matrix, the RPC surface, the input table, and **"how to add a new prop / button / interactable / carryable in under 10 lines"** with a worked example.
4. Updated `README.md` (controls), `docs/ARCHITECTURE.md`, `docs/STATUS.md`, `docs/HOUSE_AND_HAND.md`, and `docs/ROADMAP.md` where behavior changed.
5. Updated and extended tests.
6. A **manual QA checklist** for the user (carry/throw items and players, punch/parry, disconnects, elevator, reset) so they can verify on a real 2+ player session.

## 10. Final report format

When done, reply with:
- **What changed:** new structure map (folders/classes) in a short tree.
- **What was removed:** with one line of reasoning each.
- **Decisions to review:** input scheme, ragdoll authority model, any behavior you re-tuned.
- **Unverified:** everything that could only be checked by running Godot.
- **Known gaps / next steps:** anything you saw and did not touch.

Definition of done: a teammate can open `docs/INTERACTION.md`, add a new prop and a new button by following it, and nothing else in the codebase needs to change.

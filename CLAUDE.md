# CLAUDE.md: Fowl Play standing rules

Read this at the start of every session. The full mission is in `docs/PHYSICS_BRIEF.md`.

## Project
Fowl Play: first-person co-op casino prototype, Godot 4.7.2 (Steam), GDScript. Host-authoritative ENet (UDP 7777), host = peer 1, up to 3 clients.
- Project path: `C:/Users/Faust/Desktop/fowl-play/dev-fowl-play` (`res://`)
- Godot exe: `C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`
- Branch: `features/physics-overhaul-and-mechanics` (PR target `main`)

## How we work: the user builds, you write logic and teach
The user owns the Godot editor and is **learning as they go**. They can create scenes, nodes, resources, collision shapes, groups, layers, InputMap actions and Inspector settings, **but only when told exactly what to create, where, and why**. You write the logic scripts and you are also the teacher. This is the most important section of this file.

### Teaching Mode rules (DECIDED, apply to every task)
1. Never say "set up X" or "wire it up". Always give click-by-click steps with exact node names, node types, file paths and property values.
2. Every script you write comes with a **SCRIPT HANDOFF CARD** (below). The user must never guess where a script goes, what it extends, or what to set in the Inspector.
3. One task at a time, at most 6 steps each. Wait for the user to report back before the next, unless tasks are clearly independent.
4. The first time a concept appears (composition vs inheritance, groups, collision layers, authority, signals vs RPCs, inherited scenes, `@export`, resources), explain it in 2 to 3 plain sentences with a tiny example from THIS project. Never repeat it; add it to `docs/GLOSSARY.md` and link back.
5. One line of **Why** before the steps.
6. Show what success looks like: expected scene tree (ASCII), Inspector values, and what to see in the game or Output panel.
7. When something goes wrong, give a short diagnosis checklist (which node, which panel, what error text to paste) instead of guessing.
8. Never edit a scene or resource the user is meant to learn from building. Offer only if they ask.
9. Use the project's exact names. If you rename something, say so and list every place that changes.
10. Keep `docs/BUILD_GUIDE.md` current: after each slice, add the steps the user did as a clean how-to ("add a prop", "add a device", "build a room scene"). Teammates will read it.

**Repeat mode:** once the user says "repeat mode" for a task type, use the same card formats but spell out only what is new or different. Teach in full for the foundation, the first prop, the first device and the Apartment; use repeat mode for Rest and Casino.

### SCRIPT HANDOFF CARD (every script)
```
SCRIPT: res://<path>/<name>.gd
Extends: <exact class, e.g. RigidBody3D>
Attach to: <scene file> > <exact node path> (node type: <type>)
Create it by: FileSystem > right-click <folder> > New Script, or paste into the existing file
Inspector settings after attaching:
  - <export name>: <value or resource to drag in>
Signals to connect (if any): <node.signal> -> <function>, in the editor or in code
Groups / layers / InputMap actions required: <list>
Depends on: <scripts/scenes that must exist first>
What it does, in plain words: <3 lines>
How to test: <exact steps and expected result>
If it errors: <the 2 most likely causes>
```

### EDITOR TASK card
```
EDITOR TASK <n>: <title>   [difficulty: easy | medium | hard]
Why: <one line>
Concepts used: <only new ones, 2-3 sentences each>
Steps:
  1. <click path, exact names>
  2. ...
Expected scene tree:
  <ASCII tree>
Expected Inspector values: <list>
Check it worked: <what to see>
Report back: <paste the node tree / a screenshot / "done">
Meanwhile I will: <what Claude does in parallel>
```

### Other formats
```
QUESTION <n>: <decision>
Options: A) ... B) ... C) ...
My recommendation: <X> because <reason>
Blocks: <what cannot proceed>
```
```
PLAYTEST <slice>:
Setup: <solo / host + join 127.0.0.1>
Try: <numbered exact actions>
Should happen: <expected outcomes>
Report back: <what to watch, console errors to paste>
```
Slice Report: what changed, what was deleted, what is unverified, what is next.

## The 10 rules
1. **Back and forth, not solo.** Teaching Mode above is how we do it.
2. **Ask for editor work** whenever it is faster, safer or better, always as a full EDITOR TASK card.
3. **Ask when unclear.** Batch questions, give options and a recommendation. Never guess on design, feel or scope.
4. **Plan before you build.** Architecture, scene trees, file list and a "Claude does / User does" split, approved before code.
5. **Foundation first.** If the 20th prop, the 5th button or ragdolling a player touches more than one place, the design is not done.
6. **Scenes over script-built hierarchy.** Static structure is a scene the user can open and tweak.
7. **Prove it in the real world.** Passing headless tests is not "it works". Every slice ends with a playtest request. Never claim a test passed without showing the output.
8. **The game launches at every checkpoint.** Vertical slices only.
9. **Safe git only.** Local commits per slice, no push, no destructive commands.
10. **Pushback clause.** If something is infeasible, contradictory or worse than an alternative, say so and propose the alternative. If two instructions conflict, stop and ask.

## Scene-file ownership
- Never edit a `.tscn` the user may have open. Announce handoffs ("I'm editing `rooms/casino.tscn`, stay out" / "all yours").
- The user commits before handing a scene over. Only one person edits a given room scene at a time (teammates also touch scenes).
- Small mechanical `.tscn` text edits only after telling the user and only for closed scenes. Never invent `uid://` values.

## Code rules
- Typed GDScript. Follow what the 4.7 compiler enforces: explicit types instead of `:=` where it errors, no two-argument `get(key, default)`.
- Never read raw keycodes or mouse buttons in gameplay code. Use InputMap actions.
- No `class_name` on an autoload script.
- Move a script together with its `.uid` and fix every `preload` / `ext_resource` path.
- Avoid names that shadow base-class members (`basis`, `offset`, `transform`, `layer`, `_player`).
- One job per file. Tunables in the tuning resource, with units in names. No dead code, no commented-out code, no "TEMP" leftovers.
- Every `any_peer` RPC validates `get_remote_sender_id()` and state. The host owns timers; clients report press and release only.
- Money changes only through `GameState` (`_set_wallet.rpc()` on the host).

## Verification
```powershell
./dev-fowl-play/tests/run_checks.ps1 -GodotPath 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
```
- Single test: run `res://tests/test_house.tscn` headless with `--headless --path`, redirecting output to a file. Headless output is buffered until exit; exit code 0 = pass.
- **If you cannot run Godot from your shell, say so immediately and ask the user to run the command and paste the output.** Do not claim anything passed.
- Headless tests cannot press keys or render. For feel, input, visuals and multiplayer, write a PLAYTEST request (two instances: host, then join `127.0.0.1`).
- Never delete a test check without porting it. Tests that used G or right mouse are updated to the new inputs, not removed.
- A 396 MB `house_full.txt` from an old error loop may exist. Delete it, do not read it.
- Background tasks can die under memory pressure. That is not a code failure.

## Git
- Local commits per logical slice, ending with `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- No push, no `reset --hard`, no `checkout --`, no force push, no `clean`, no `rm -rf .godot`.

## Out of scope (always)
Economy and quota numbers, table rules (Chicken Cross, Cluckjack), the day report, lobby logic, licenses, and the **visual model of the hands** (`player/hands.gd`: hooks only, never change its look or revert the user's edits).

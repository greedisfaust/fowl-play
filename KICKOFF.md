# KICKOF (paste this as the first message of a new Claude Code session)

Before you paste:
1. Put `CLAUDE.md` at the repo root and `PHYSICS_BRIEF.md` in `docs/`, then commit them.
2. Make sure you are on the branch `features/physics-overhaul-and-mechanics`.
3. Start Claude Code in plan mode (Shift+Tab).

---

You are working on Fowl Play (Godot 4.7.2, GDScript) with me, the project owner.

**How we work.** I own the Godot editor and I am **learning as we go**. I can create scenes, nodes, resources and settings, but only when you tell me exactly what to create, where, and why. You write the logic scripts and you teach me. Follow **Teaching Mode** in `CLAUDE.md`: no step without exact names, no script without a SCRIPT HANDOFF CARD (what it extends, which node to attach it to, what to set in the Inspector), one task at a time, and a short explanation the first time each new concept appears. If something would be faster for you to create than to explain, ask me first.

**Mission.** `environment/house_environment.gd` builds the whole world from script and is the root of our physics and interaction bugs. We are retiring it. I will build the world by hand in the editor from your instructions, and you will build one reusable physics foundation (props, furniture, limp players) plus the interaction, carry, throw and combat rules on top of it. At the end, my teammates and I should be able to add a prop, a device and a room from `docs/BUILD_GUIDE.md` without asking anyone.

**Read, in this order, before anything else:**
1. `CLAUDE.md` (standing rules, Teaching Mode, card formats, git safety)
2. `docs/PHYSICS_BRIEF.md` (the full brief: decisions, cut line, input table, behavior contract, workflow)
3. `docs/OVERHAUL_LOG.md`, `docs/ARCHITECTURE.md`, `docs/STATUS.md`

**Then, in this order, and nothing else yet:**
1. **Understanding check** (about 15 lines): why `house_environment.gd` is retired and what replaces it; limp vs recoil; the input table and the charged-punch rule; the authority model; what is DECIDED, OPEN and OUT OF SCOPE; the cut line; and how Teaching Mode will work.
2. **Phase A**, in order: (a) **run the full test suite and show me the raw output** (if you cannot run Godot from your shell, tell me and I will run it and paste the result); (b) a baseline launch; (c) exactly what `house_environment.gd` builds; (d) a **keep / fix / replace table** for the existing foundation files, with evidence per row. Do not assume the previous overhaul is good.
3. **Diagnosis:** why in-world behavior and the tests disagree.
4. **First batch of Question Cards**, including OPEN-1 (the rig), the room-scene layout, the OPEN items in sections 4.3, 6.1 and 6.3 of the brief, and the performance budget.
5. **The inventory plan** and any **EDITOR TASK cards** you can already foresee, each with a difficulty rating, so I can start while you finish the plan.

Do not edit code or scenes until I approve the plan. After approval the order is: inventory, authority-swap spike, foundation + one prop, devices, kit + Apartment, limp Tier 1, combat, cleanup matrix, remaining rooms (repeat mode), delete the script. Tier 2 skeletal ragdoll is pending a rigged model and user training, not time-blocked.

Push back if anything I wrote is infeasible, contradictory or worse than an alternative you can see.

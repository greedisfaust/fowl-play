export const meta = {
  name: 'update-overhaul-prompt-combat-input',
  description: 'Scan prompt/repo/docs for input/combat references, then design exact prompt edits for the new Q/E/F/MOUSE1 input map and recoil-vs-limp body reactions',
  phases: [
    { title: 'Scan', detail: 'Read the overhaul prompt, grep the repo, and read related docs for every input/combat reference' },
    { title: 'Design', detail: 'Synthesize exact old_str/new_str edit pairs plus question cards and verification greps' },
  ],
}

const PROMPT_PATH = 'C:/Users/Faust/Desktop/fowl-play/claude_code_collab_physics_overhaul_prompt.md'
const REPO_ROOT = 'C:/Users/Faust/Desktop/fowl-play/dev-fowl-play'

const DESIGN_SCHEMA = {
  type: 'object',
  properties: {
    edits: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          old_str: { type: 'string' },
          new_str: { type: 'string' },
          reason: { type: 'string' },
        },
        required: ['file', 'old_str', 'new_str', 'reason'],
      },
    },
    questionCards: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          decision: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
          recommendation: { type: 'string' },
          blocks: { type: 'string' },
        },
        required: ['decision', 'options', 'recommendation', 'blocks'],
      },
    },
    verification: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
  required: ['edits', 'questionCards', 'verification', 'summary'],
}

phase('Scan')
const scanResult = await agent(
  'TASK: Scan the Fowl Play overhaul prompt and repo for every input/combat reference.\n\n1) Read the full file: ' + PROMPT_PATH + '. Report: (a) the exact current text of rule 16 "One input map, no overloaded actions" with line numbers; (b) the exact current text of the "Limp = knockdown = ragdoll" section with line numbers; (c) EVERY line mentioning Q, E, G, RMB, right-click, mouse1, left click, punch, parry, throw, drop, limp, ragdoll, recoil, jiggle, stun, charge — with line numbers and exact verbatim quotes.\n\n2) Grep the repo at ' + REPO_ROOT + ' recursively for: Q, E, G, RMB, mouse1, left click, right click, punch, parry, throw, drop, limp, ragdoll, recoil, jiggle, stun, charge, knock.down in .gd/.md/.tscn/.tres files. Prioritize player/combat.gd, player/focus.gd, player/carrier.gd, player/player_state.gd, player/player.gd, interaction/interactable.gd, environment/house_environment.gd, lobby/text_terminal.gd, tables/press_button.gd, dev-fowl-play/*.md, docs/*.md. Report every match as file:line + line text.\n\n3) Read docs if present: README.md, docs/ARCHITECTURE.md, docs/STATUS.md, docs/INTERACTION.md, docs/OVERHAUL_LOG.md under the repo root. Report every mention of punch/parry/throw/input/limp/ragdoll/recoil/jiggle/stun/charge/knock-down with file:line and quotes.\n\nReturn ALL findings verbatim with file:line references.',
  { label: 'scan-prompt-repo-docs', phase: 'Scan' }
)

phase('Design')
const design = await agent(
  'You are designing edits to the Fowl Play overhaul prompt based on these USER decisions:\n\nUSER DECISIONS (apply all):\n- Q HOLD = Charged Punch: player lunges/charges a few meters forward to throw a punch WITH ANIMATION.\n- F = Parry: both hands come to the face and block the user\'s face, for parry visualization.\n- E = ALTERNATIVE for pressing buttons; PRIMARY for buttons = MOUSE1 (Left Click).\n- Right Click is NOT punch and NOT throw. Remove Right Click from combat entirely.\n- HOLD Q covers BOTH: Throw (when holding an item: charge then release) AND Charge Punch / Quick Punch (when not holding: lunge forward a few meters with animation).\n- Quick press Q DROPS the held item (replaces G); the G / DROP InputMap action is removed.\n- Quick press Q when NOT holding = Quick Punch (a jab).\n- Q is state-disambiguated: holding -> {quick press: drop, hold: throw}; not holding -> {quick press: quick-punch jab, hold: charge-punch lunge}.\n- NEW reaction: "Fluid interactive / jiggle body" recoil. When a body is hit by a quick punch or by a thrown physics object, it recoils (moves back / reacts) then returns to its original state. TEMPORARY, NOT limp/ragdoll, NOT an Interactable component.\n- This recoil is distinct from CHARGE PUNCH, which puts the target into RAGDOLL/LIMP (stunned, cannot move). That incapacitation is the problem to implement.\n\nTASK: Update the "One input map, no overloaded actions" rule and the "Limp = knockdown = ragdoll" section (add the recoil vs limp distinction), plus any other rules affected by these decisions. Produce exact old_str/new_str edit pairs (old_str must be verbatim text drawn from the scan results), plus question cards for anything still ambiguous, plus verification greps.\n\nSCAN RESULTS:\n' + JSON.stringify(scanResult) +
'\nReturn a single JSON object: edits (file/old_str/new_str/reason), questionCards (decision/options/recommendation/blocks), verification (list of grep commands), summary (plain text). No markdown fences.',
  { label: 'design-prompt-edits', phase: 'Design', schema: DESIGN_SCHEMA }
)

return { scans: scanResult, design: design }
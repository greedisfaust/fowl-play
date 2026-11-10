# Asset register and sourcing policy

| Asset | Location | Source / rights status | Action |
| --- | --- | --- | --- |
| Bundled UI font | `dev-fowl-play/assets/fonts/ui_font.ttf` | Existing project file; author and license not recorded | Owner must identify font and retain its license, or replace before distribution |
| Godot project icon | `dev-fowl-play/icon.svg` | Existing Godot-style project icon; provenance not recorded in repo | Verify applicable Godot artwork terms before public packaging |
| Primitive world, hands, tables, generated screens | Scene and script resources | Existing project-authored content; repository has no overall license | Team confirms ownership and code/art distribution terms |
| Cluckjack cards, board and signs | `tables/cluckjack/` | Procedural geometry and text created for this project; no external pack imported | Covered by whatever license the project owners adopt |

No new marketplace asset is required for the first Cluckjack slice: generated
card faces, felt and signage can match the primitive prototype without adding
an unverified dependency.

Candidate for a later art pass: [Kenney Playing Cards Pack](https://kenney.nl/assets/playing-cards-pack),
whose publisher page lists Creative Commons CC0 (checked 10 November 2026).
This pack is **not installed**. Keep its license file and source URL if imported.
Do not describe a recommended pack as already included.

For every future itch.io/marketplace import, record author, direct pack URL,
version/download date, exact license, included files, modifications, and required
credit here. Include the upstream license beside the asset. Verify redistribution,
commercial use and modification rights; a free download alone grants none of
those. Avoid uploading large unused packs. Preserve required notices in exports.

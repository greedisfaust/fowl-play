# Asset register and sourcing policy

| Asset | Location | Source / rights status | Action |
| --- | --- | --- | --- |
| Bundled UI font | `dev-fowl-play/assets/fonts/ui_font.ttf` | Existing project file; author and license not recorded | Owner must identify font and retain its license, or replace before distribution |
| Godot project icon | `dev-fowl-play/icon.svg` | Existing Godot-style project icon; provenance not recorded in repo | Verify applicable Godot artwork terms before public packaging |
| Primitive world, hands, tables, generated screens | Scene and script resources | Existing project-authored content; repository has no overall license | Team confirms ownership and code/art distribution terms |
| Cluckjack cards, board and signs | `tables/cluckjack/` | Procedural geometry and text created for this project; no external pack imported | Covered by whatever license the project owners adopt |
| Kenney Furniture Kit 2.0, 13 GLB subset | `dev-fowl-play/assets/kenney/furniture/` | [Kenney publisher page](https://kenney.nl/assets/furniture-kit), downloaded 10 November 2026; CC0 | Original `LICENSE.txt`, source record and SHA256 manifest included; unchanged binaries, runtime scaling/collision proxies |
| Room shells, dusk sky, city silhouettes, damage marks, lore plaques, cups/chips | `environment/`, `interaction/` | Created for this project using Godot geometry, materials and text | Covered by the project owners' eventual license |

Cluckjack card faces and signs remain procedural. The room/prop update imports
the Kenney subset above; no other marketplace packs are installed.

Candidate for a later art pass: [Kenney Playing Cards Pack](https://kenney.nl/assets/playing-cards-pack),
whose publisher page lists Creative Commons CC0 (checked 10 November 2026).
This pack is **not installed**. Keep its license file and source URL if imported.
Do not describe a recommended pack as already included.

For every future itch.io/marketplace import, record author, direct pack URL,
version/download date, exact license, included files, modifications, and required
credit here. Include the upstream license beside the asset. Verify redistribution,
commercial use and modification rights; a free download alone grants none of
those. Avoid uploading large unused packs. Preserve required notices in exports.

# Validation Record

All checks below concern the browser design preview. They do not establish Godot implementation, iPad touch behavior, GPU performance, real 3D collisions, shared-world synchronization or server-side persistence.

## Earlier design checks — 2026-10-06

- Chrome at a 1024px-wide viewport: both 1448 by 1086 scene images loaded and were visually inspected.
- A/B switching, catalog selection and hiding/restoring the catalog worked without horizontal page overflow.
- Direction A was subsequently selected. The complete interaction design still awaits user acceptance.
- Character selection, outdoor placement, turning, color changes, removal confirmation, undo and indoor arrangement were exercised.
- Preview objects survived a reload in local browser storage.
- Swing sitting, animated swaying and leaving were checked. Full-room, editing-lock, offline and save-failure simulations displayed their corresponding states and retry controls.
- Five flow states had no horizontal page overflow. Main scene controls met the 48 by 48 CSS pixel target in that run.

## Tree placement and furniture revision — 2026-10-06

Before the fix, a tree at scene coordinates (24%, 78%) could not be confirmed. After the fix, the same location allowed placement and the object remained in the scene. Catalog selection found a free initial spot automatically.

Beds, tables, chairs and flower pots now use different relative sizes with ground-contact anchors and no white icon-card background. The interior was visually inspected. Turning is sprite mirroring only, not verified 3D rotation.

## English repository and six-language UI — 2026-10-06

This section is updated with the final checks for the localization and source upload task. Prior Chinese-only screenshots were superseded by the current English and multilingual preview evidence. No game-development completion is implied.

- `python3 scripts/check.py`: PASS, 133 nonempty messages with identical keys across six catalogs; English filenames and source/document text; valid local HTML references.
- `node --check`: PASS for `flow.js`, `i18n.js`, `directions.js` and `scripts/browser-check.js`.
- `scripts/browser-check.js` executed in an isolated Chrome context at 1024px viewport width: PASS in all six languages. It exercises actual control clicks for character selection, tree placement at (24%, 78%), interior bed placement, turning, removal, undo, simulated save failure and retry, swing animation and exit.
- Language switching retained the chosen character, placed objects and active placement draft. Object accessibility labels and scenario options translated correctly.
- All five main views and the removal, reset, disconnected, full-room, occupied and failed-save states were checked for message coverage and panel bounds. No horizontal page overflow was detected in this run.
- Both concept directions, category selection, catalog hide/show and page titles passed checks in all six languages.
- Reload restored three saved test objects and the selected German locale. The comparison page also read the saved locale.
- English and German interiors were visually inspected. A missed scenario-option translation found in that inspection was fixed and all six language checks rerun. Final screenshots: [English](screenshots/interior-en.png), [German](screenshots/interior-de.png).
- Git initialized locally on `main`; no commit or push was performed.

Limits: translations have not had native-speaker review; browser checks are not physical iPad testing. No public service, Godot build or multiplayer server was deployed.

## Source transfer verification — 2026-10-06

The authorized SSH destination was inspected and was empty before transfer. The complete source tree, including initialized Git metadata, was uploaded without deletion flags. SHA-256 comparison verified 51 files with zero mismatches and zero extra remote files. The repository checker also passed on the remote host. Remote Git reported `main` with no commits, matching the local repository. No server was started.

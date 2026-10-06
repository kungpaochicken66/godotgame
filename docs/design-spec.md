# Design Specification

Status: direction A, a closer view into the town, was selected on 2026-10-06. The interaction preview and later furniture revision await acceptance. The target is a Godot 3D iPad app; HTML demonstrates the design only.

## Confirmed direction

Two to four cartoon children freely decorate a shared home. Use warm, rounded 3D forms with gentle colors and a relaxed atmosphere. Houses can be entered; landscaping and furniture are freely available with duplicates. A swing has a simple play animation. The initial scene contains trees, a path and a pond.

## Composition

- **A, selected:** a closer oblique camera emphasizes characters and the feeling of walking through town; the catalog is at the bottom. Large-area placement will require camera movement.
- **B, comparison:** a higher oblique camera reveals more paths, water and open ground; the proposed catalog is on the right. Characters and furniture appear smaller.
- `design/directions.html` preserves both original scene concepts. The interactive flow is in `design/index.html`.

## Shared design values

- Paper `#f5f1e7`, panel `#fffdf6`, text `#344d40`, muted text `#69796a`.
- Accent green `#557c5e`, soft green `#e5eddc`, warm yellow `#edcf81`.
- Rounded system sans-serif with language-appropriate fallback. Typical body text 16px and touch labels around 18px.
- Spacing steps: 8, 12, 16, 24 and 32px. Panels use 24px corners; buttons use 16px corners.
- Landscape iPad is the current proposal. Main controls target at least 48 by 48 CSS pixels; actual Godot and device sizing remain unverified.
- Keep partner and save state at the top. Avoid currency, advertising, quests and upgrade indicators competing with the town.
- Permit translated labels to wrap. Catalog items can scroll horizontally. Dialogs scroll internally when needed. Language selection remains available outside the scene.

These values are project proposals, not measurements extracted from the reference game.

## Interaction proposal

1. **Choose a character:** four provisional human-child cards, without a registration form. Names and appearance are placeholders for the creator's ideas.
2. **Explore:** enter through the cabin hotspot or open the swing interaction. Real walking and camera behavior await a Godot touch prototype.
3. **Place:** choose an item, point or drag to open ground, turn it, optionally change a house color, and confirm. Invalid positions disable confirmation; cancellation preserves the prior layout.
4. **Edit:** select a placed item, move, turn or put it away. Removal asks for confirmation and can be undone during the current session. Undo across reloads is outside the preview.
5. **Interior:** arrange chairs, a round table, bed, flower pot and rug in an empty room, then exit. Preview indoor and outdoor lists are stored separately; this is not per-house game persistence.
6. **Swing:** sit, see a looping sway, and leave. The preview uses vector artwork to communicate timing, not a Godot character animation.

## Exceptional states

The preview simulates an editing lock, full room, lost connection and failed save with retries. Their presence in the preview does not confirm shared-world semantics. Character uniqueness, camera controls, house removal contents and real recovery behavior remain open requirements.

## Art and placement limits

Scene images are generated concepts, not Godot screenshots or importable 3D models. Background objects cannot be edited. The original prop atlas uses transparent sprites with different relative dimensions, bottom contact points, depth ordering and a small perspective scale adjustment. Turning mirrors a sprite; it does not rotate a 3D object.

The tree-placement bug was reproduced at the lower lawn and fixed with scene-specific placement regions. The catalog now collapses after placement so it does not obscure newly placed furniture. Approximate two-dimensional footprints avoid overlaps; these do not establish actual 3D collision behavior.

The selected A background is still more textured than the reference gameplay. Future models should simplify grass, foliage and wood grain, favor clear silhouettes and consistent character/door/furniture scale, and leave visible walking and decorating space. See [visual-references.md](visual-references.md).

## Language design

Supported locales: `en`, `zh-CN`, `ja`, `es`, `fr`, `de`. English is the source and default. Native language names appear in the selector. The setting persists in local browser storage where available and is shared across both preview pages. Switching language must preserve the current view, selected character, placed items and unsaved placement draft.

All UI messages, object and character names, placement hints, dialogs, scenario options, image descriptions, document titles and accessible labels are translated. Six JSON catalogs hold non-English copy; identifiers, comments, paths and documentation remain English. Translation is local and requires no external translation service. Missing messages fall back to their English source; automated checks require complete catalogs. Copy has not been reviewed by native-language speakers.

For the future Godot app, reuse the same message inventory and approved wording with Godot's localization facilities. The preview implementation does not count as Godot localization.

## Assets and evidence

`scene-a.png`, `scene-b.png`, `interior.png` and `props.png` are generated original concepts. Generation prompts are preserved in `design/prompt-*.txt`. The prop atlas is not extracted Nintendo artwork. New screenshots are evidence of the browser preview only; historical screenshots with superseded Chinese-only UI have been removed during repository organization.

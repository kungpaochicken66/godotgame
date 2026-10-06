# Gameplay References and Art Revisions

On 2026-10-06, the user requested actual Animal Crossing gameplay screenshots as style references. Exterior and interior images were opened and visually compared in a browser. They were not imported as game assets.

## Sources

- [Nintendo: Create your getaway](https://animalcrossing.nintendo.com/new-horizons/create/)
- [Nintendo: outdoor furniture screenshot](https://animalcrossing.nintendo.com/new-horizons/assets/img/create/thumbnail-acnh-create-decorating-1-2x.jpg)
- [Exterior house screenshot and article](https://exp.gg/zh_tw/130857/)
- [Interior furnishing screenshot and article](https://www.shacknews.com/article/148209/acnh-switch-2-upgrade)

## Visual observations

These are design judgments, not measured game parameters.

- Shapes are readable. Grass and foliage textures are restrained compared with our concept; dense flowers, rocks and wood grain should not carry the entire visual appeal.
- Children, doors, chairs, tables and trees need a consistent scale. A chair must look usable rather than like a tiny sticker.
- Interior floors are usable placement space. Furniture feet and bases should contact the floor; white icon cards do not convey furniture in a room.
- Tooltips should stay near edges and leave enough visible space for placement.

## Preview changes already made

- Reproduced the old blanket rejection of positions below 68% scene height, which prevented trees on the lower lawn. Placement now uses scene-specific ground regions.
- Automatically find a free spot and allow click or drag repositioning. Approximate ground footprints, rather than tree canopy sizes, determine overlap.
- Added an original transparent `props.png` atlas with distinct relative object sizes, bottom anchors and mild perspective scaling. Removed white icon-card frames.
- Collapse the catalog after placement; Add more opens it again.
- Preserved the generation prompt in `design/prompt-props.txt`.

## Still requiring art and Godot work

The selected A background still has dense textures. Sprite mirroring cannot validate real rotation, lighting, occlusion or collision. Percentage-based placement regions approximate concept artwork and must be replaced by actual Godot ground and object geometry.

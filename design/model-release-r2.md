# Model release r2: wall and ceiling models in the game

Game Code integration of the 42 furniture references the Modeling lane's backlog records as `model_complete` (`tools/nookipedia-model-production/progress/backlog_inventory.csv`): 38 ceiling items (references 151-188) and 4 wall items in version 2 (references 113, 115, 119, 143; their v1 was excluded from release r1 by the small-size band). 42 references map to 42 unique models; none was in the game before. Frozen inputs are read only and never modified; `scripts/build_furniture_r2.py` (`--check` verifies) checks the batch digests and every GLB hash, copies the GLBs byte-for-byte to `game/assets/models/`, and generates the catalog block "production models r2" and the names in six languages (`design/model-release-r2-names.tsv`, original generic names).

## Sources

| batch | BATCH_MANIFEST sha256 | used |
|---|---|---|
| `b011-furn-r2` (FROZEN 2026-10-07T11:53:20Z) | `1b10021d3e43daa9d83f80e9aabad6fcfca9d308ceb04fdca809ba292ac86abe` | 31 assets (27 ceiling, 4 wall) |
| `b012-furn-r3` (FROZEN 2026-10-07T12:17:30Z) | `cd8e0084737c79dac2f8ad01eb6a0cf9d2b48e3209cad7704fea212a4ceafda5` | 11 ceiling assets: the repaired versions named by the DEFECT NOTICE (`INTEGRATION_QUEUE.md`, validator v2.4 inside-out pieces); the b011 versions of these 11 are **not** used |

## Included (42)

| ref | reference | asset id | name in game | anchor | class | lamp | batch | GLB sha256 |
|---|---|---|---|---|---|---|---|---|
| 113 | Bone doorplate | `bone_doorplate` | Bone name plate | wall | small | - | b011-furn-r2 | `12a84c554ed47a694fc7609884249670220bdb4c3a48eab1b7a2960b1c4beba2` |
| 115 | Breaker | `breaker_box` | Breaker box | wall | small | - | b011-furn-r2 | `41e38c30e94ab10586535d2e93c62748d505f40d450f6513be0e5f7d55d5e70f` |
| 119 | Bug poster | `insect_chart_poster` | Insect chart | wall | small | - | b011-furn-r2 | `5024cf3bef17da24ec8a03768b861ddf1536cd27b18766f64a00a24798c1251c` |
| 143 | Deer decoration | `antler_wall_mount` | Antler wall mount | wall | small | - | b011-furn-r2 | `8a053fe6c7dc5aa40a1999d961a11b9422cb84b9da653a8a80fb7513acbe7f7d` |
| 151 | Candle chandelier | `candle_ring_chandelier` | Candle ring chandelier | ceiling | medium | Light0 | b011-furn-r2 | `d55bd51b96087ae575558dac7211c02be94ea1758c7a64e0cd157301e642ef9b` |
| 152 | Ceiling fan | `ceiling_fan_light` | Ceiling fan with light | ceiling | large | Light0 | b011-furn-r2 | `7388e460c5bf84b070d96bdb46f5eb1abdead12594ab8b75f84961d87de952df` |
| 153 | Ceiling spotlight | `ceiling_spotlight_bar` | Spotlight bar | ceiling | medium | Light0 | b012-furn-r3 | `fe2c69116f3c90bad99fe66ecaa48b7ea4e9aae4e1cece88990fa3a6135e332f` |
| 154 | Chandelier | `crystal_chandelier` | Crystal chandelier | ceiling | medium | Light0 | b012-furn-r3 | `48cb832ec18a3dd9905313ca35f338be27b39299601987a725f80056a4fa6a48` |
| 155 | Disco ball | `disco_ball` | Mirror ball | ceiling | medium | - | b011-furn-r2 | `0a7b5ae4076cfc2a710fab70963b3375241305a6be07bc3c4e1f7f8d7cb67860` |
| 156 | Drapery | `swag_drapery` | Draped valance | ceiling | medium | - | b011-furn-r2 | `1dc9681f64a98ece43ebfa391a8517663760757861f9dcced834f8889aa7c679` |
| 157 | Dreamy hanging decoration | `dreamy_star_strings` | Hanging star strings | ceiling | small | - | b011-furn-r2 | `2b05373db248b1d49df78109b6f1c85cb97f5f91b2e7d57bb55c0a9f025cd95b` |
| 158 | Dual hanging monitors | `dual_hanging_screens` | Twin hanging screens | ceiling | medium | - | b011-furn-r2 | `8839e7fe5922cf707228a09e9ce7fb37d695f847bb03a5c53a3907b32a1556f2` |
| 159 | Enamel lamp | `enamel_pendant` | Enamel pendant lamp | ceiling | medium | Light0 | b012-furn-r3 | `4f9a8159357c48718f3020cbc2a9b8a59157f997578be574afa542fe6cde7f4d` |
| 160 | Festival lantern | `red_paper_lantern` | Red paper lantern | ceiling | medium | Light0 | b012-furn-r3 | `6c14e56866ff2c8f91114d437738ac639bbdaccef8c6d0499ef31a48fa33933f` |
| 161 | Festival-lantern set | `paper_lantern_string` | String of paper lanterns | ceiling | medium | Light0 | b012-furn-r3 | `1a75428d516fe3a5bf2fe5bfaaf7266889a2b744e848e34f600bdb0de1dd2710` |
| 162 | Fluorescent light | `fluorescent_fixture` | Tube light | ceiling | medium | Light0 | b011-furn-r2 | `24b5e1e4fb95c4a471dafe8ce6b9b0f6d015965e74720f2413937341fc929d4f` |
| 163 | Hanging cube light | `hanging_cube_lamp` | Hanging cube lamp | ceiling | medium | Light0 | b011-furn-r2 | `41b57607a53a1d4e84244142c0b1410a7db5a8e61e33b3d5e28d2e18d5ff549a` |
| 164 | Hanging glowing moss | `glowing_moss_strands` | Glowing moss strands | ceiling | small | Light0 | b011-furn-r2 | `2707252b3aff4b9141ce5a934998a626371337f4151f9b896f850a167d8d5847` |
| 165 | Hanging guide sign | `hanging_guide_board` | Hanging direction board | ceiling | medium | - | b011-furn-r2 | `c2bb625d338583d6d837c93409cb92883b51ae678a71610fc369b08a38a1bfb0` |
| 166 | Hanging lightbulb | `bare_bulb_pendant` | Bare bulb pendant | ceiling | medium | Light0 | b011-furn-r2 | `d8ac5e0b0bb543e614263e180ac28d4d160072c391659e3778f722cbcee7e81a` |
| 167 | Hanging monitor | `hanging_screen` | Hanging screen | ceiling | small | - | b011-furn-r2 | `9ca47ae412a06d3ff870215160c5c09dfe1d4c3f5e5cc8cdb1bddade3cbcf246` |
| 168 | Hanging shelves | `hanging_plant_shelves` | Hanging plant shelves | ceiling | medium | - | b011-furn-r2 | `0e2af6f28a98500f3ee9977b5182a2a5b408b7d965af909f54debad4b5749de0` |
| 169 | Hanging sign | `hanging_shop_sign` | Hanging shop sign | ceiling | small | - | b011-furn-r2 | `d405ecade7606022803adb82f08fd3cd4a70fe7549d98393266a4ba6d3ea8975` |
| 170 | Hanging stage lights | `stage_light_bar` | Stage light bar | ceiling | medium | Light0 | b011-furn-r2 | `7901c23b2f83911f7063a1a1f65fc70020b437e5aff85be1f5b67ffaf13e0fb5` |
| 171 | Horizontal split curtains | `split_curtain_wide` | Wide split curtain | ceiling | medium | - | b011-furn-r2 | `3d35c92d3a0335ed368d0e4296b59e9db0eaacfe5592235d84e95a549d06bc30` |
| 172 | Imperial lamp | `umbrella_pendant` | Parasol pendant lamp | ceiling | medium | Light0 | b012-furn-r3 | `fab372673595feeab9483394ff21c29fd898b3aaa5d1a861ab66a3bf77d77c9a` |
| 173 | Milk-glass lamp | `milk_glass_pendant` | Milk-glass pendant lamp | ceiling | medium | Light0 | b011-furn-r2 | `f54d2d9b64350b499e97d5e569c43ecd0a1b8c30dfb6c7207814d6e7df0e021d` |
| 174 | Moroccan lights | `tiered_lantern_cluster` | Lantern cluster | ceiling | medium | Light0 | b012-furn-r3 | `259e7c35a72c013a85e155d975048d260f05ee0afb3bad095bc7ab7f6c976e03` |
| 175 | Nordic pendant light | `nordic_pendant` | Nordic pendant lamp | ceiling | medium | Light0 | b012-furn-r3 | `cbba4a0fb7d460c4941988634403d131d6fea56e0f4569745aee14e2b4dace08` |
| 176 | Ornithopter | `paper_ornithopter` | Paper flying machine | ceiling | medium | - | b011-furn-r2 | `c77bbbbfb3eaa2c6f44bcc5720fd631a501289a395d3a9425456f3878c516d19` |
| 177 | Paper-chain ceiling garland | `paper_chain_garland` | Paper-chain garland | ceiling | medium | - | b011-furn-r2 | `25e90bc56afafc354ade939e4f9eab97073ecfd3e4de08377206c920d75f21b6` |
| 178 | Range hood | `kitchen_range_hood` | Kitchen range hood | ceiling | medium | Light0 | b011-furn-r2 | `5f11b223b91bcf9467dbcd4b505ebd7f0db497f401aa7b6fcd8d3140bb7f5174` |
| 179 | Round light fixture | `three_globe_fixture` | Three-globe light | ceiling | small | Light0 | b011-furn-r2 | `c0681e68d57106d4d43cf006e64b8ee65d2a8ff51bdaf722c4918f50df725b75` |
| 180 | Shaded pendant lamp | `drum_shade_pendant` | Drum-shade pendant lamp | ceiling | medium | Light0 | b012-furn-r3 | `6070ed8cbe06a0fa2d54d6826a26541f9f1ac7f687968c4eb8cf1e610ad02d6d` |
| 181 | Simple shaded lamp | `cone_shade_pendant` | Cone-shade pendant lamp | ceiling | medium | Light0 | b012-furn-r3 | `408f70592be5457f80b360247fc0939bfb7f5f5754b471c3ca449cbce2140a6b` |
| 182 | Spiral chandelier | `spiral_crystal_chandelier` | Spiral crystal chandelier | ceiling | medium | Light0 | b011-furn-r2 | `baeb44e76ec810271fc834971d9f5a2774bf6d108f25d738c948830461c9a1bd` |
| 183 | Stained-glass light | `stained_glass_pendant` | Stained-glass pendant lamp | ceiling | small | Light0 | b011-furn-r2 | `1f536142ca6ceb5f587e8e8175c9f8367c3a4380e2f2a5fa2efd152287d7e68c` |
| 184 | Vertical split curtains | `split_curtain_tall` | Tall split curtain | ceiling | medium | - | b011-furn-r2 | `82f819f86b94d4fa9020c31bd92ffba89db5cde485ee6e5ed9b887d79ff3d93b` |
| 185 | Vine garland | `ivy_vine_garland` | Ivy garland | ceiling | medium | - | b011-furn-r2 | `6ef3763d51816e9e60105f72b0a67d5c97efc247093694764dcd2c87f9eac33e` |
| 186 | Wood-shade lamp | `barrel_wood_pendant` | Wooden barrel lamp | ceiling | medium | Light0 | b012-furn-r3 | `cb92d837c9617f968174f67da3c0f75c14e26bfcdb6e455a464466fb2f53f30d` |
| 187 | Wooden pendant light | `wood_frame_pendant` | Wood-frame pendant lamp | ceiling | medium | Light0 | b011-furn-r2 | `b8eb3a3e2aa151258654f974605c7c2f6e58d682a3419b70bdde8b1429ef601c` |
| 188 | Zen light | `paper_lattice_pendant` | Paper lattice lamp | ceiling | medium | Light0 | b011-furn-r2 | `0da891134f25df933e7431d090849cf93f5c9abdb84fa1780c2fade2487f8592` |

Already present before r2: none of the 42 asset ids or references. Excluded: the 11 superseded b011 versions above; the 19 deliberately blocked references stay blocked (50 1-Up Mushroom, 52 ACNH Nintendo Switch, 57 Aloha-edition carrying case, 238 Champion outfit, 367 Champion wig, 373 Cinnamoroll hat, 400 Cinnamoroll sneakers, 417 Force ReBoots, 421 Hello Kitty shoes, 422 Hero Boot Replicas, 426 Hylian boots, 428 Kerokerokeroppi boots, 430 Kiki & Lala shoes, 464 Kerokerokeroppi socks, 466 Kiki & Lala socks, 532 Luigi 'stache, 533 Mario 'stache, 582 Hero's sword and shield, 584 Ink tank); wearables are a separate integration ([docs/wearables.md](../docs/wearables.md)).

## Game behavior

- **Placement:** indoors only, through the toy box (tab Cozy things; the existing Ceiling and On the wall filters). Ceiling items hang from the 2.8 m ceiling at their hook (origin, top y = 0), any floor point inside the room, one fixed facing; wall items hang on the back or left wall at their mount height (center at max(1.5 m, h/2 + 0.35 m)), away from doors, stairs and the window. Neither blocks walking. The existing gates are unchanged: room edge, overlap of hanging items (circles) and of wall items (along the wall), wall openings, the small-class height band (0.2-0.45 H for every `small` item), indoors only.
- **New rule, headroom:** a hanging item and a standing item (including anything on a table top or carried by a host) may not meet: the lowest r2 pendant ends at 1.93 m, the room-high garden pavilion (2.81 m) cannot stand under a ceiling item and no ceiling item can hang into it. The authority checks it on place and move ("Not enough room under the ceiling there.", six languages); the placement ghost shows the same result. It also applies to the older bird mobile. Saves that already contain such an overlap still load.
- **Lamps:** 25 items carry a `Light0` marker and light up in the evening like the other modeled lamps; the other 17 are decorations.
- **Antler wall mount:** its frozen model's vertical center is 7.1 cm below its origin (the lab's G3 gate checks the back plane and x only); the game shifts the model by the catalog field `model_offset` instead of rewriting the frozen GLB.
- **Interactions:** none beyond placement and lighting; nobody sits on, uses or rides these items.
- **Toy box names (r13b):** every card shows its whole name, broken only between words, in up to three lines at 13-16 px; a card widens only when a single word cannot fit. No two things in one tab share a name in any of the six languages (unit-checked; this also fixed three older duplicates: Japanese "Plush bear" and "Garden bed", Spanish "Plush bear").
- **Messages during placement (r13b):** a new placement clears the last placement message, and a message never lies over the placement tools; it moves below (or above) them first.
- **Saves and network:** ordinary catalog kinds with the mount height stored as `y`, like the release r1 wall items: no protocol change (protocol 9), older saves load unchanged.

## Limits

- Ceiling items could not be turned in r13b (rotation was fixed at 0, so long garlands, curtains and light bars always ran left to right). **r15** lets them turn in 45-degree steps with Turn, while hanging and when editing.
- The ceiling fan does not spin, the mirror ball does not turn and the screens show nothing (no new interaction systems).
- Wall items may still overlap tall standing furniture against the wall (existing release r1 behavior).
- Visual checks of these models are the Modeling lane's model reviews; in-game rendered acceptance needs the Mac run, device acceptance a device. Many lamps in one room each add an evening light; performance on device is not measured.

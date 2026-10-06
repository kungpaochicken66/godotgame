# Our Little Town — Product Requirements

Status, 2026-10-06 (later the same day): a playable Godot 4.7.2 prototype, "Lantern Lane", implements the requirements below (see [game-design.md](game-design.md) and [HANDOFF](../HANDOFF.md)). It has not run on an iPad yet, and no server is hosted. The working title and content are agent proposals awaiting the creator's acceptance.

Repository documentation, filenames, identifiers and comments use English. User-facing copy supports English, Simplified Chinese, Japanese, Spanish, French and German. Non-English copy belongs in `design/locales/`.

## Product and audience

An eight-year-old creator wants to design a cozy town, including gardens, houses and recreational objects, and play with friends on iPads. She contributes object designs and ideas; this does not imply an in-game modeling editor or a gender-specific palette.

Two to four children, each at home on a different internet connection, decorate the same shared home. Everyone can modify it. The first release focuses on freely decorating a pleasant home, rather than gathering resources or unlocking items. All supplied furniture, houses, landscaping objects and swings are available from the beginning, free of in-game currency, with repeated copies allowed.

Players choose a cartoon child, enter the town, place complete houses and landscaping, decorate indoors and outdoors, and use a swing with a simple animation. The initial town already has paths, trees and a pond, all intended to be editable in the game. The shared home automatically saves and survives everyone leaving and returning.

The product is an installed **iPad app built in Godot, in 3D**. The browser files are design previews only. A supplied multiplayer technical discussion is background material, not an approved feature list. In particular, whole-house placement does not imply voxel digging or wall-by-wall construction.

Art direction references the rounded forms, gentle colors and relaxed atmosphere of Animal Crossing. Characters remain human children. Original characters, objects, buildings and UI are required; reference screenshots are not game assets.

## Requirement register

A direction or principle being confirmed does not mean all interaction rules are settled. Preview coverage is not implementation or product verification. All release stages remain unassigned.

| ID | Requirement | Confirmation | Design location | Development stage | Implemented | Verified | Released |
|---|---|---|---|---|---|---|---|
| R-001 | Freely decorate the shared home | Core direction confirmed | [game-design.md](game-design.md) | Godot prototype | Yes: toy box, ghost placement, move/turn/paint/put away, undo | Unit + rendered tour + network test on EC2; not on iPad | No |
| R-002 | Cartoon child characters | Character type confirmed; looks are proposals | Character creator | Godot prototype | Yes: 8 preset nicknames, 5 skin tones, 5 hairstyles, 6 hair colors, 3 outfits, 8 colors, emotes | Rendered screenshots (software GL) | No |
| R-003 | Place complete houses, choose colors, enter and furnish them | Scope confirmed | Cottages and dollhouse interiors | Godot prototype | Yes | Unit, session, tour and network tests | No |
| R-004 | Furnish indoors and outdoors, all items available immediately | Confirmed | 22-item toy box | Godot prototype | Yes | Unit + tour | No |
| R-005 | Join a shared world | Proposal implemented: one town per server, preset identity, no login | [multiplayer.md](multiplayer.md) | Godot prototype | Yes: join, late-join snapshot, leave | Real client processes on one host | No |
| R-006 | Edit existing landscaping (trees, flowers, paths, ponds) | Confirmed | Default town of editable items | Godot prototype | Yes | Unit + tour | No |
| R-007 | Swing with simple animation | Confirmed | Swing, plus seesaw, benches, sofa, bed | Godot prototype | Yes, with occupancy | Tour (sway measured) + network test | No |
| R-008 | iPad, 2–4 people | Confirmed | Landscape touch HUD; generic iPad export preset | Godot prototype | Touch-first UI; export preset | Layout checked at 4:3 and iPad Air 5 aspect in software render only; no device run | No |
| R-009 | Everyone can modify the same home | Rules implemented (locks, seats, own-undo) | [game-design.md](game-design.md) | Godot prototype | Yes | Session + network tests | No |
| R-010 | Free objects including duplicates | Confirmed | Toy box | Godot prototype | Yes; capacity 300 town / 40 per room (pending iPad measurement) | Unit | No |
| R-011 | Automatic persistence | Implemented: debounced atomic save + .bak | Session | Godot prototype | Yes (solo, host, server) | Session test (incl. damaged save) + server restart test | No |
| R-012 | Connect across separate household networks | Approach chosen: hosted authoritative server over wss | [multiplayer.md](multiplayer.md) | Server code ready | Server and client code yes; hosting no | Loopback only; no internet/NAT/TLS test | No |
| R-013 | Rounded, gentle 3D cartoon art | Direction A camera kept | Procedural toy models | Godot prototype | Yes, placeholder-quality original art | Visual review of software renders; final art acceptance pending | No |
| R-014 | Six-language UI | Confirmed | `game/locale/` | Godot prototype | Yes, with bundled CJK fonts and localized app name | Automated catalog/font checks + six-language rendered tour; no native-speaker review | No |

## Acceptance drafts

These define intended game behavior, not results already achieved.

- **Free objects:** Given a first-time player, when the catalog opens, every object supplied by this version can be selected without tasks, resource collection or game currency. After placing one, another copy remains available. Total object capacity needs iPad measurement.
- **Persistence:** Given completed automatic saving of indoor and outdoor layouts, when all players leave and return, houses, furniture, landscaping and swings retain their arrangement without a manual save action. Save timing and the acceptable loss window on failure remain open.
- **Cross-household multiplayer:** Given 2–4 iPads using different home networks, when players join the same home and arrange objects, they see one another and the shared results. A late joiner receives the existing layout. This has not been implemented or tested.
- **Interiors:** Given a placed cabin, when a player enters and arranges furniture, the furniture belongs to that cabin, is visible to other visitors and participates in the shared save. Entry rules and capacity remain open.
- **Landscaping:** Given an initially decorated town, players can move and turn supplied trees, flowers, path pieces and ponds. Freehand path drawing and pond shaping are outside the confirmed first-release scope.
- **Swing:** A player can trigger actual sitting/swaying animation and leave. Scoring, winning and complex minigame controls are outside the proposed initial interaction. Occupancy and editing while in use remain open.
- **Languages:** A user can select any of the six supported languages. Visible labels, hints, dialogs, object names, scenario descriptions and accessibility labels use that language. Selection persists where browser storage is available and switching preserves the layout. English is the default and fallback. Game-level language settings must later be implemented in Godot.

## Decisions and history

The following is an English translation and consolidation of the user's statements on 2026-10-06; it is not a claim to reproduce the original wording verbatim.

1. The supplied attachment described technology, not gameplay. The intended game is a cartoon life-sim with placeable buildings and furniture.
2. The creator is eight, wants to design gardens, houses and recreational facilities, and participate in object design and ideas. She will play on iPad with other children.
3. The first focus is freely decorating a beautiful home. Every supplied furniture item is available on day one.
4. One shared home can be modified by everyone. Houses are placed as complete objects, with color selection and furniture. Facilities should actually animate, but stay simple.
5. Houses can be entered and furnished. The first facility is a swing. The initial town contains paths, trees and a pond.
6. Characters are cartoon children. Landscaping uses prepared objects that can be moved and turned. Simultaneous player count is 2–4.
7. All supplied objects are free to choose, duplicates are allowed, and the home saves automatically. Friends connect from their own homes over the internet.
8. The user chose an installed iPad app, not a browser game, and specified Godot.
9. Animal Crossing was selected as the overall visual reference. Direction A, with a closer camera and bottom catalog, was selected from the two concepts.
10. The user reported that trees could not be placed and indoor furniture had poor proportions and appearance, then requested actual gameplay screenshots as reference. The preview was revised; acceptance remains pending.
11. The user requested English repository code and documents, six UI languages, Git initialization, and upload to a designated existing SSH destination. This authorizes the requested upload, not a live game deployment or paid distribution.

## Proposals that remain unconfirmed

- One fixed room, direct character selection, no game registration or login, as suggested by the technical attachment.
- One editor per object at a time; other objects remain editable. An occupied swing cannot be moved or put away.
- An undo action for mistakes. The preview supports in-session undo, but this does not settle shared-world undo semantics.
- No in-game AI, quests or economy in the initial version. AI was never requested and is not a blocker for the already requested work.
- The creator supplies drawings or spoken ideas that are turned into game assets during production.
- Landscape orientation and the provisional character names, appearances, item selection and error flows.

## Open decisions

| Topic | Remaining decision |
|---|---|
| Joining | Fixed room or invitation; identity, character reuse, access and rejoining rules |
| Movement and camera | Actual touch movement, camera controls and switching between walking and decorating |
| Shared edits | Concurrent edit conflicts, undo ownership and occupied facilities |
| Houses | What happens to interior furniture when a house is put away or duplicated |
| Persistence | Save timing, failure recovery and disconnected changes |
| Capacity and performance | Supported iPad baseline, frame-rate target and object limits |
| Distribution | Testing/install route and eventual release method |
| Creative participation | How the creator submits designs and approves assets |
| Completion | Session length, success measures and unacceptable failure cases |

An optional future in-game AI feature does not block current work. Distribution decisions should be resolved before their corresponding delivery stage, not treated as proof that game development has started.

## Scope exclusions

- Do not replace gameplay design with technical architecture.
- Do not lock furniture, houses, landscaping or swings behind collection, currency or tasks.
- Do not assume a voxel world, freehand terrain editing or an in-game asset editor.
- Account-free joining is a proposal from the attachment, not yet a confirmed exclusion.

## Distribution research boundary

An earlier 2026-10-06 check recorded TestFlight external testing as a possible route, requiring review for the first external test build, and the Apple Developer Program's advertised annual price of USD 99. These are historical planning facts, not a selected distribution route or spending authorization. Recheck current eligibility, pricing and local billing before acting. No membership purchase or distribution has occurred.

Sources: [Apple Developer Program](https://developer.apple.com/programs/) and [external tester invitations](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

## Current progress

All fourteen requirements are implemented in the Godot prototype and covered by automated checks on the EC2 host (see [validation.md](validation.md)). None is verified on an iPad or across real home networks, and none is released. Earlier open decisions about joining, shared edits, houses and persistence now have proposed rules in [game-design.md](game-design.md), awaiting the user's acceptance.

Next product work: build and run on the target iPad (iPad Air 5, iPadOS 26.6.1) from the user's Mac; review the art and translations with the creator; choose hosting for the town server ([multiplayer.md](multiplayer.md)).

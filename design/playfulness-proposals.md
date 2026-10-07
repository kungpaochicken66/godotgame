# Playfulness Proposals — Design Handoff

Status: 2026-10-06. Originally a design handoff. The user then authorized implementing **all eight** features (A–H). The section "Corrections and implementation specs" below supersedes the original text wherever they differ; implementation status is tracked in [HANDOFF.md](../HANDOFF.md). Written against the current game (revision 2: the toy box with 30 items, Cozy Spots and lanterns, three-story houses, table tops, five animal friends, emotes, the evening bell, scrapbook and photos, solo play and 2–4 player multiplayer).

## Ground rules every proposal keeps

- **Unlimited furnishing stays untouched.** Every toy box item is free, with unlimited copies, from the start. Nothing here unlocks, earns, costs, consumes or limits items. Gifts are copies, and found treasures are celebrations, not stock.
- **Invitations, not quests.** Each activity is optional, has no failure, timers or penalties, and never blocks building. This respects the scope exclusion "do not lock … behind collection, currency or tasks" and the open "no quests or economy" proposal.
- **Kind multiplayer by design.** There's no free text: preset nicknames, emotes and picture cards only, as today. Nothing lets one child take or break another child's creation without the existing lock, undo and put-away rules.
- **Easy for an eight-year-old to read.** Icons and short phrases in the six existing languages, big touch targets, and a celebration you can see and hear for every success.

## Corrections and implementation specs (supersede the text below)

### Identity: a nickname is not an identity

- Each device creates a random **player id** on first launch: 128 bits, hex, stored in `user://settings.cfg` and never shown. It is sent with `rq_join`.
- The authority keeps a **roster** in the town save: player id → last nickname, outfit color, last seen. Gifts, hearts, visits and credits refer to player ids. Nicknames are only for display.
- The id identifies a device, not a verified person: there are no accounts, logins or passwords. Deleting the app makes a new id. A shared iPad is one player. This is enough for kind, low-stakes play; it is not security.

### Where things persist (three tiers, no pretending)

| Town type | Where the town lives | Who can receive things while they are away |
|---|---|---|
| Solo | this device | only this device's own player |
| Hosted on a device ("Host on this device") | the host device's save; available only while the host is running the game | friends receive gifts when they next join **that host's** town while it is running |
| Dedicated server (`--server`) | the server's save; available whenever the server runs | real asynchronous delivery across homes, **only if** someone operates an always-on server |

No always-on server is provided or authorized here: hosting purchases, public deployment and credentials are out of scope. So **offline cross-home delivery is not claimed**. A gift waits in the town where it was wrapped and is opened when the recipient is in that town. The code works the same on a dedicated server, and the network tests exercise that path on loopback.

### Implementation specs (MVP, all optional, nothing gated)

| | Feature | What is built | Stored in the town save? | Network authority |
|---|---|---|---|---|
| A | Animal wishes | 20 wish templates (4 per animal) for outdoor arrangements; one active wish per town; a wish card when the animal is tapped; a "Wish" tab pinned first in the toy box; on success the animal plays there, a sticker goes in the scrapbook crediting everyone present, and sometimes the animal leaves a present (C) | yes: `wishes` (active wish, stickers) | the authority picks and checks; one completion even with simultaneous edits |
| B | Hide-and-seek | Golden acorn rounds. The hider hides where they stand (town or any room); seekers get a 0–4 warmth level from the server; the acorn appears only within 2 m; tap to find. The acorn starts glowing after 3 minutes as a gentle hint, never a timer. Solo: an animal hides it outdoors. | no (session only) | the authority holds the hidden spot; clients never get it early |
| C | Gift bundles | "Wrap" in the item editor turns any placed item into a present addressed to a roster player or "anyone"; only that player (or anyone) can unwrap it into the normal item. At most 3 unopened presents per recipient. | yes: `gift` on the item | the authority wraps and unwraps; protocol bump |
| D | Little gardens | A new "Garden bed" item. Its sprout, bud and bloom stages grow while children play: a "Water" action and a slow growth tick about every 60 s with someone outdoors. A full bloom takes a few minutes of play, there is no punishment and it never wilts. | yes: `growth` on the item | the authority grows and waters |
| E | Dance parade | A "Party" action at the bell: for 30 s the music speeds up with a light beat, animals parade around the Wishing Tree, lanterns twinkle and children who join dance | no (session only) | the authority starts and ends it and sends the parade state |
| F | Open-house visits | Inside any room, a heart button leaves or removes your heart sticker (one per player per room). The living room has a guest book of everyone who visited the house. No counts across houses, no rankings. | yes: `hearts`, `visits` | the authority records hearts and visits |
| G | Photo activities | 8 photo ideas checked from deterministic scene facts at the shutter (who and what is on screen, the space, evening, seats, table tops), not image AI. Completed ideas go in the scrapbook. | yes: `photo_ideas` | the client computes the facts it rendered; the authority records them |
| H | Weather | A weather vane by the bell cycles sunny → rain → autumn → snow. It changes the sky, ground tint, particles and puddles, and Pip splashes in rain puddles. Decoration only; everything stays placeable. | yes: `weather` | the authority sets it; everyone sees the same |

### Wall and ceiling placement (enables the pending models)

- `anchor: "wall"` items attach to a room's back or left wall. They are stored with `x`, `z` on the wall, a height `y` and the wall's facing. They must fit within the wall and stay clear of doors, stairs and the window, and of each other.
- `anchor: "ceiling"` items hang from the room ceiling (y = 2.8). They overlap only with other ceiling items.
- Neither kind blocks walking, and neither is allowed outdoors.
- The wall clock (center height 1.5) and the bird mobile (hangs 0.78) become placeable.

## The candidates (8)

| # | Feature | One-line pitch | Solo | 2–4 friends |
|---|---|---|---|---|
| A | **Animal wishes** | Pip, Bramble, Wooly, Biscuit or Tumble shows a picture bubble ("a puddle near a bench!"); arrange it and the animal throws a happy party | ★★★ | ★★★ (wishes are shared; anyone can help) |
| B | **Hide-and-seek treasure** | One child hides a glowing "golden acorn" anywhere, even in a drawer room on floor 3; the others hunt with warmer/colder sparkles | ★★ (animals hide it) | ★★★ |
| C | **Gift bundles** | Wrap any toy box item with a bow and leave it on a friend's doorstep; they unwrap it next time they play | ★ (gifts from animals) | ★★★ (works even when friends play at different times) |
| D | Little gardens | Plant seed patches that sprout, bud and bloom over real hours; friends water them together | ★★ | ★★ |
| E | Dance party parade | Ring the bell twice for a party: music switches to a bouncy variation, animals and children line up and parade around the Wishing Tree | ★ | ★★★ |
| F | Open house tours | Put up a "Visit my house!" sign; visitors leave heart stickers in rooms they love, shown on a little guest book | ★ | ★★ |
| G | Photo challenges | Picture prompts ("everyone on one bench", "the elephant by the pond") fill scrapbook pages when a photo contains them | ★★ | ★★ |
| H | Weather days | Gentle rain with puddles (Pip's favorite), autumn leaves or snow, chosen with a weather vane; items look seasonal | ★★ | ★★ |

**Originally not recommended first** (all eight are now being implemented, using the specs above):
- **D:** real-time growth invites "come back later" pressure and needs time-sync rules.
- **E:** fun, but mostly an animation spectacle; it fits as an add-on to A.
- **F:** a voting or heart economy risks comparison between children.
- **G:** reliable "is it in the photo?" detection is costly.
- **H:** a large art pass, and the weather is decoration more than play.

## Recommended top three

These were chosen because together they cover the three play modes an eight-year-old moves between:

- **A, Animal wishes:** making something for someone (solo or together).
- **B, Hide-and-seek treasure:** a lively shared game with friends in real time.
- **C, Gift bundles:** care for friends who aren't online at the same time.

All three reuse what already exists (animals, Cozy Spot-style arrangement checks, rooms and stairs, emotes, the toy box, saves and the network authority). None needs new art beyond a few small props and icons.

---

### A. Animal wishes ("Can you help Pip?")

**Play loop:**
1. An animal walks up to the child and shows a picture bubble: two to three icons from the toy box and a place icon. For example: blanket + pond for Pip, three flower patches + bench for Bramble, lamp post + swing for Wooly, table + two chairs + teddy indoors for Biscuit, a stepping-stone trail to the orchard for Tumble.
2. The child decorates anywhere it fits; the rule is "near each other", like Cozy Spots.
3. When the arrangement exists, the animal runs there and plays its hobby on it, with a confetti burst and a thank-you sticker in the scrapbook naming the helpers.
4. A new wish appears a while later.

**Repeat appeal:**
- About 6–8 wish templates per animal, with random item choices from that animal's tastes, so the same wish rarely repeats.
- Wishes use the arrangements the child has already built: a "helped" wish stays fulfilled while the arrangement exists, so redecorating can make new wishes possible.
- Each animal's scrapbook page fills with stickers, with no total to "complete" and nothing locked.

**Touch flow:**
- Tap the animal (as now) to see its wish card, which shows the icons large.
- An "I'll help!" button opens Decorate with the wished items **pinned first** in the toy box. One tap still shows everything.
- A small wish chip near the friends bar shows the current wish. Tapping it makes the camera pan to the animal.
- No timers. "Not now" hides the bubble.

**Asset reuse:**
- Animals, hobbies and animation exist.
- The arrangement detection is the same proximity code as `cozy_spots.gd`.
- The scrapbook card layout exists.
- New: the picture-bubble UI built from the existing thumbnails, 5 sticker icons (SVG in `ui_kit.gd`), and one "party" animation per animal (a variation of the existing hop and dance poses).

**MVP scope:**
- 5 animals × 4 wish templates (20). One active wish for the whole town at a time.
- Wishes are outdoors only (animals don't go indoors), except Biscuit's "tea party with my teddy", which the animal checks from the cottage door. Or leave indoor wishes out of the MVP.
- Stickers in the scrapbook; localized wish labels as icon + short phrase.

**Effort:** about 4–6 developer days (logic 1.5, UI 1.5, animation 1, tests and translations 1–2).

**Save and network risks:**
- The active wish and the earned stickers must live on the authority and in the save. Proposal: `wishes: {active: {...}, stickers: [{animal, wish, by: [nicknames], t}]}`. This is a new optional save key, so no schema bump, and old saves have none.
- The authority picks and checks wishes (like lanterns), so two friends can't double-complete one wish.
- Risk: a wish could be impossible in a crowded or small town. Mitigation: pick only wishes whose items are placeable in town right now (the `find_free_spot` check).
- Network: one small broadcast when a wish starts and one when it completes.

**Acceptance examples:**
- Given Pip's wish "blanket near pond", when any child places a picture blanket within 3.6 m of a pond, then within 2 s Pip runs there and splashes, everyone sees confetti, and the scrapbook shows a Pip sticker crediting every child present.
- Given an active wish, the toy box lists the wished items first and still offers all 30 items; no item is hidden or locked.
- Given a fulfilled wish, when the blanket is later moved away, the sticker stays and nothing is taken back.
- Given four players, when two complete the same wish at the same moment, exactly one completion is recorded and both children are credited.

**Playtest plan:** see the shared plan below. Watch for whether the child can "read" a wish without help within 10 s.

---

### B. Hide-and-seek treasure ("Golden acorn")

**Play loop:**
1. One child taps **Hide** and carries a glowing golden acorn (a tiny prop that is *not* a toy box item and never counts toward anything) to any spot in the town or any room of any house: under a tree, on a table top, upstairs.
2. Everyone else hears a chime and a countdown of picture dots (no reading needed).
3. Seekers walk around. The closer they get, the more sparkles fall around them and the faster a soft bell ticks. In rooms, the floor and room chip glows on the right floor.
4. The finder gets a cheer emote for everyone and becomes the next hider.

**Repeat appeal:**
- The three-story houses, the larger countryside and furniture give endless hiding spots, and the town the children built *is* the level.
- Turns rotate naturally.
- Solo: an animal hides the acorn (Tumble hides it somewhere far, Bramble in the garden), which also shows off the map.

**Touch flow:**
- One big **Hide & seek** button in the emote row.
- The hider sees "Put it somewhere!", then drags the acorn like a placement ghost, valid anywhere a small item fits, including a table top. Confirm.
- Seekers just walk (tap to walk). Tapping the acorn when close finds it.
- An always-visible "Stop game" ends it.

**Asset reuse:**
- Placement ghost and validation, including table tops: the acorn uses the `small` / `tabletop_eligible` rules but is not saved as a town item.
- Rooms and portals, sparkle particles (Cozy Spot sparkles), emotes and SFX tones.
- New: an acorn model (a few procedural spheres) and a proximity "warmth" indicator.

**MVP scope:**
- One round at a time for the whole town: hide, seek, found.
- Warmth is based on distance plus "same room" (floors count as far apart).
- Solo mode has animals hide the acorn in town only.
- No scores or timers shown; an optional 3-minute soft hint after which the acorn glows brighter.

**Effort:** about 4–5 days (round state machine on the authority 1.5, hide placement 1, warmth UI and sound 1, tests 1–1.5).

**Save and network risks:**
- The round state is **session-only**. Don't save it: if everyone leaves, the round simply ends, so there's no save risk.
- **Fairness:** the acorn's exact position must not reach seekers' devices, or a curious tap could reveal it. The authority sends each seeker only a warmth level, and the acorn node is created on a client only when that seeker is within about 2 m in the same space.
- The hider leaving mid-round ends the round kindly ("Sky went home; the acorn hops back to the Wishing Tree").
- The hiding spot must stay reachable: validate it with the same rules as placement, and keep doorways and stairs clear.

**Acceptance examples:**
- Given three players, when Sunny hides the acorn on the attic table top, then Sky and Peach see "Find the golden acorn!" and no acorn until they are within 2 m in the attic. Their warmth rises as they climb to floor 3.
- When Sky taps the acorn, everyone sees Sky cheer, the round ends, and Sky becomes the hider. Nothing in the town save changes.
- Given the hider disconnects, the round ends within 2 s for everyone, with a friendly message.
- Solo: Tumble hides the acorn outdoors, and the child can find it within the larger map with the warmth hints alone.

**Playtest plan:** shared plan below. Measure whether rounds last 1–4 minutes (the sweet spot) and whether children ask for "one more".

---

### C. Gift bundles ("A present for you!")

**Play loop:**
1. In Decorate, a child picks any toy box item, taps **Wrap as gift**, chooses a paper color and a friend's nickname (or "anyone"), and the present appears on that friend's cottage doorstep or by the Wishing Tree.
2. The next time the friend plays, even hours later, the present sits there with a bow.
3. They tap it: it unwraps with confetti, a picture card shows who it came from, and the item is placed right there as a normal item they can move.

**Repeat appeal:**
- Asynchronous care when friends play at different times, which is very common for kids in different homes.
- Choosing *which* item and *which* paper is creative, and opening presents is a reliably delightful moment.
- Solo: animals occasionally leave a little present (a flower pot from Bramble, a ball game invitation from Biscuit) to show the loop.

**Touch flow:**
- In the item editor, add one more button, "Gift" (a bow icon), next to Turn / Paint / Put away.
- Then pick a friend: chips with their preset nicknames and outfit colors. Then **Leave it here**.
- Recipient: the present glows and a bubble says "From Sky!". Tap to open.

**Asset reuse:**
- Toy box, thumbnails and the existing item models; the present is a rounded box with a ribbon (procedural); paint swatches for the paper.
- Friend chips from the HUD, confetti and SFX, and the table-top and doorstep placement rules.

**MVP scope:**
- A gift is a wrapper around one item of any kind, sitting on the doorstep or at the tree.
- Addressed to one preset nickname or "anyone".
- Unwrapping turns it into a normal town item at the same spot, or the nearest free spot.
- A visible limit of about 3 unopened presents per recipient keeps doorsteps tidy. This is not a limit on furnishing: the giver's toy box is unchanged.

**Effort:** about 3–4 days (model and save 1, UI 1, network and authority 0.5, tests and translations 1–1.5).

**Save and network risks:**
- Presents must persist, so add an optional save key with schema-compatible loading. Proposal: items get an optional `"gift": {"to": nick or "", "from": nick, "paper": i}`; the item keeps its normal kind, and the gift wrapper is just a flag. Old saves have no gift flag, and an old app ignores unknown keys. A protocol bump is still recommended so mixed versions don't see mismatched behavior.
- Wrapped items need placement rules (doorstep clearance must not block the door: put presents beside it, not in the door zone) and must not count toward Cozy Spots until opened.
- Identity: nicknames are not unique, so "to Sky" is ambiguous if two children choose Sky. In the MVP, presents to a nickname can be opened by any child currently using that nickname; this is documented. A unique player ID would need an account or device ID decision, which is open.
- Locks and undo: wrapping is an edit like paint. Unwrapping is a server action that both the giver and the receiver can undo only through put-away; keep it simple.

**Acceptance examples:**
- Given Sunny wraps a teddy for Sky and leaves, when Sky joins later, a present with a bow sits beside Sky's (or the nearest) cottage door, with "From Sunny" on tap.
- When Sky taps it, it unwraps into a normal teddy at that spot that Sky can move, paint or put away. Sunny's toy box still offers unlimited teddies.
- Given a server restart before Sky joins, the present is still there (persistence).
- Given four presents for one child, the fourth is refused with "Sky's doorstep is full of presents!", and nothing is lost.

**Playtest plan:** shared plan below. Include one session where friends play at different times on the same day.

---

## Comparison

| | A Animal wishes | B Hide-and-seek | C Gift bundles |
|---|---|---|---|
| Best for | solo and co-op building | 2–4 friends live | friends at different times |
| New art | stickers, bubble UI | acorn, warmth indicator | present box, bow icon |
| Effort | 4–6 days | 4–5 days | 3–4 days |
| Save change | optional `wishes` key | none (session only) | optional `gift` flag on items |
| Network | authority picks and checks; 2 events | authority holds the hidden position; per-seeker warmth | authority wraps and unwraps; protocol bump |
| Main risk | impossible wishes in crowded towns | leaking the hidden position to clients | nickname ambiguity |

**Suggested order:** C (smallest, and it uses the existing persistence and network), then A (the biggest solo appeal), then B (the most networking care). Each can ship on its own.

## Shared playtest plan (for any of the three)

- **Who:** the creator (8) alone first, then with 1–3 friends on separate iPads or iPhones. Sessions of 20–30 minutes, with a grown-up observing quietly and not explaining unless asked twice.
- **Before:** a fresh town and one "lived-in" town (a migrated real save).

| Feature | Observe | Success signal |
|---|---|---|
| A | time to understand a wish card without help | under 10 s; the child fulfils at least 2 wishes and asks "what does Wooly want now?" |
| B | round length; turn-taking; frustration | rounds of 1–4 minutes; children ask for another round; no one hides in an unreachable spot |
| C | whether children send gifts without prompting; reaction when opening | at least one unprompted gift per child; visible delight; gifts don't clutter doorsteps |

- **All:** note any moment of confusion, tears or "it took my thing". Count unprompted laughs and "look!" moments. Check readability in at least two languages and touch comfort on the smallest device.
- **After:** a 3-question picture survey (smiley scale): "Was it fun?", "Was it easy?", "Do you want to play it again tomorrow?". Record the results in `docs/validation.md` as **device playtests**, separate from automated checks.

## Open decisions for the user

1. Is "invitations" (A) acceptable given the earlier "no quests" proposal? A is written to have no rewards, gating or failure.
2. Should gifts (C) be addressed by nickname only (simple, ambiguous), or wait for a device or player ID decision?
3. Should solo hide-and-seek (B) have animals hide the acorn indoors too? That requires animals to enter houses, which they don't do today.
4. Which feature should go first: the recommended order is C, A, B.

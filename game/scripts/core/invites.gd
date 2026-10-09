## Cooperative invitations (design/playability-8-12.md F10): a child invites the
## friends in town to an activity or to help edit a place on display. Each friend
## sees one card per inviter (a newer invitation replaces the older one) with
## Join and Not now; nothing happens to anyone who says Not now, and the inviter
## only hears about friends who join. Pure rules, unit-tested; the authority
## keeps the cards (not saved).
extends RefCounted

## Kind -> what the card says (after "%s invites you:"). Preset texts only.
const KINDS := {
	"fetch": "Play fetch with Biscuit",
	"animal": "Play with the animals",
	"trail": "Walk my trail",
	"music": "Make music together",
	"story": "Be in my story",
	"party": "Dance at the party",
	"hide": "Play hide-and-seek",
	"help": "Please help me edit",
}
## Cards disappear on their own after this many seconds.
const LIFETIME := 120
## The same invitation is not sent again within a few seconds (a second tap keeps the card).
const COOLDOWN := 3


static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


## A card for one friend: who, what, and where (space and spot) to go on Join.
static func card(from_pid: String, from_nick: String, kind: String, target: String, space: String, at: Vector2, now: int) -> Dictionary:
	return {"from": from_pid, "nick": from_nick, "kind": kind, "target": target, "space": space,
		"x": snappedf(at.x, 0.01), "z": snappedf(at.y, 0.01), "t": now}


## Adds a card to a friend's inbox, merging by inviter. Returns the inbox.
static func add(inbox: Dictionary, c: Dictionary) -> Dictionary:
	inbox[c["from"]] = c
	return inbox


## Cards still showing at `now`.
static func live(inbox: Dictionary, now: int) -> Array:
	var out := []
	for from in inbox:
		if now - int(inbox[from]["t"]) <= LIFETIME:
			out.append(inbox[from])
	out.sort_custom(func(a, b): return int(a["t"]) > int(b["t"]))
	return out


## Can this child send this invitation now? `last`: when they last sent this same
## invitation (same kind and target); a different invitation is never held back.
static func check(kind: String, actor_space: String, others: int, last: int, now: int, display_owner: String, pid: String) -> String:
	if not is_kind(kind):
		return "That invitation is not on the list."
	if others <= 0:
		return "No friends are in town right now."
	if now - last < COOLDOWN:
		return "Your friends have your invitation."
	if kind == "help" and display_owner != pid:
		return "Put this place on display first, then ask friends to help."
	return ""

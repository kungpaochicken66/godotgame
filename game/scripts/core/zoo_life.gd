## What the zoo's ground and water animals do (design/zoo-and-world-journeys.md sections 6.4, 10
## and 22): their own routines, their answers to children and to toys, as data. The brain
## (zoo_brain.gd) reads it; monkeys have their own anchor-based play there.
extends RefCounted

## Per species:
##   speed     metres per second when it walks (or swims) somewhere
##   swim_speed (optional) metres per second in water, for a species that walks on land and swims (penguins)
##   move      the action name of that walk ("walk", "prowl", "trot", "swim")
##   routine   what it does by itself: [action, spots ("" = where it is), weight, dur min, dur max, cooldown, then]
##             "then" is a list of [action, seconds] done after it on the same spot
##   treat     [action, spot, seconds]: where it goes for a treat and what it does there
##   emotes    a child's emote -> its answer [action, seconds]
const LIFE := {
	"lion": {"speed": 1.1, "move": "walk",
		"routine": [["bask", ["lion_sun_rock"], 3.0, 8.0, 14.0, 25.0, [["shake", 1.2]]], ["survey", ["lion_sun_rock", "lion_ridge_south"], 2.0, 4.0, 6.0, 18.0, []],
			["yawn", [""], 1.2, 2.6, 2.6, 30.0, []], ["patrol", ["lion_ridge_south"], 2.0, 0.0, 0.0, 35.0, []]],
		"treat": ["eat", "lion_sun_rock", 3.6], "emotes": {"wave": ["nod", 2.0], "cheer": ["roar", 2.6], "heart": ["blink", 2.4], "dance": ["roll", 2.8]}},
	"lioness": {"speed": 1.2, "move": "walk",
		"routine": [["nap", ["lion_shade"], 3.0, 8.0, 14.0, 30.0, []], ["groom", ["lion_shade"], 2.0, 4.0, 6.0, 25.0, []],
			["stalk", ["lion_grass"], 2.0, 3.0, 3.0, 45.0, [["pounce", 1.2], ["roll", 1.6]]], ["peek", ["lion_den_mouth"], 1.2, 3.0, 4.0, 40.0, []],
			["yawn", [""], 1.0, 2.6, 2.6, 30.0, []]],
		"treat": ["eat", "lion_sun_rock", 3.6], "emotes": {"wave": ["nod", 2.0], "cheer": ["roar", 2.6], "heart": ["blink", 2.4], "dance": ["roll", 2.8]}},
	"tiger": {"speed": 1.3, "move": "prowl",
		"routine": [["survey", ["tiger_prowl_a", "tiger_prowl_b"], 2.0, 3.0, 4.0, 15.0, []], ["show_walk", ["tiger_log_south"], 1.6, 0.0, 0.0, 40.0, []],
			["soak", ["tiger_swim"], 2.0, 8.0, 12.0, 40.0, [["shake", 1.4]]], ["stretch", ["tiger_scratch"], 1.5, 3.0, 4.0, 30.0, []],
			["nap", ["tiger_slab"], 2.0, 8.0, 12.0, 30.0, []], ["hide", ["tiger_hide"], 1.2, 6.0, 10.0, 35.0, []]],
		"treat": ["lick", "tiger_treat", 4.0], "emotes": {"wave": ["chuff", 2.0], "cheer": ["show_walk", 0.0], "heart": ["blink", 2.4], "dance": ["roll", 2.8]}},
	"giraffe": {"speed": 0.9, "move": "walk",
		"routine": [["browse", ["giraffe_acacia_a", "giraffe_acacia_b", "giraffe_acacia_c"], 3.0, 6.0, 10.0, 12.0, []],
			["drink", ["savanna_drink"], 1.2, 5.0, 7.0, 40.0, []], ["look", [""], 1.5, 3.0, 5.0, 10.0, []]],
		"treat": ["tongue", "savanna_treat", 3.5], "emotes": {"wave": ["nod", 3.0], "cheer": ["canter", 2.4], "heart": ["blink", 2.4], "dance": ["nod", 3.0]}},
	"zebra": {"speed": 1.4, "move": "trot",
		"routine": [["graze", ["zebra_graze_a", "zebra_graze_b", "zebra_graze_c"], 3.0, 6.0, 10.0, 10.0, []],
			["dust_roll", [""], 1.0, 2.6, 2.6, 40.0, []], ["swish", [""], 1.5, 3.0, 5.0, 12.0, []],
			["drink", ["savanna_drink_b"], 1.0, 4.0, 6.0, 40.0, []]],
		"treat": ["eat", "savanna_treat", 3.4], "emotes": {"wave": ["nod", 2.0], "cheer": ["buck", 1.8], "heart": ["blink", 2.4], "dance": ["prance", 3.0]}},
	"hippo": {"speed": 0.8, "move": "swim",
		"routine": [["float", ["hippo_float"], 3.0, 8.0, 12.0, 15.0, []], ["twirl", [""], 1.5, 2.4, 2.4, 20.0, []],
			["bask", ["hippo_beach"], 2.0, 8.0, 12.0, 45.0, []], ["yawn", [""], 1.2, 3.0, 3.0, 30.0, []]],
		"treat": ["chomp", "splash_treat", 2.6], "emotes": {"wave": ["twirl", 2.4], "cheer": ["fountain", 2.6], "heart": ["blink", 2.4], "dance": ["twirl", 2.4]}},
	"otter": {"speed": 1.6, "move": "swim",
		"routine": [["float", ["otter_float_a", "otter_float_b"], 3.0, 5.0, 8.0, 12.0, []], ["dive", [""], 1.5, 2.4, 2.4, 15.0, []],
			["slide", ["otter_slide_top"], 1.5, 0.0, 0.0, 30.0, []], ["juggle", ["otter_beach"], 1.5, 4.0, 6.0, 30.0, []]],
		"treat": ["beg", "otter_beach", 2.0], "emotes": {"wave": ["paws", 2.0], "cheer": ["dive", 2.4], "heart": ["blink", 2.4], "dance": ["roll", 2.6]}},
	# zoo r2 (Everything Library six): Bao, Mabel, Pebble and Flip.
	"panda": {"speed": 0.9, "move": "walk",
		"routine": [["munch", ["panda_bamboo"], 4.0, 8.0, 12.0, 8.0, [["look", 1.6]]], ["sit_up", ["panda_rock"], 1.8, 5.0, 8.0, 25.0, [["nod", 1.4]]],
			["roll", ["panda_lawn"], 1.6, 3.0, 4.0, 30.0, []], ["nap", ["panda_shade", "panda_rock"], 1.4, 8.0, 12.0, 40.0, []],
			["look", [""], 1.0, 3.0, 4.0, 10.0, []], ["blink", [""], 0.8, 2.0, 2.0, 12.0, []]],
		"treat": ["eat", "panda_treat", 3.6], "emotes": {"wave": ["nod", 2.0], "cheer": ["sit_up", 2.4], "heart": ["blink", 2.4], "dance": ["roll", 2.8]}},
	"elephant": {"speed": 0.8, "move": "walk",
		"routine": [["dust", ["elephant_dust"], 2.5, 4.0, 6.0, 20.0, [["ear_flap", 2.0]]], ["ear_flap", ["elephant_dust"], 1.8, 3.0, 5.0, 14.0, []],
			["drink", ["elephant_waterhole"], 2.2, 5.0, 7.0, 35.0, [["spray", 2.6]]], ["spray", ["elephant_waterhole"], 2.4, 3.0, 4.0, 22.0, []],
			["trumpet", [""], 0.7, 2.4, 2.4, 50.0, []], ["graze", [""], 1.3, 5.0, 8.0, 20.0, []], ["look", [""], 1.0, 3.0, 4.0, 10.0, []]],
		"treat": ["eat", "elephant_treat", 3.8], "emotes": {"wave": ["ear_flap", 2.4], "cheer": ["trumpet", 2.6], "heart": ["blink", 2.4], "dance": ["ear_flap", 3.0]}},
	"penguin": {"speed": 0.9, "swim_speed": 1.8, "move": "waddle",
		"routine": [["preen", ["penguin_shore_a", "penguin_shore_b"], 3.0, 4.0, 7.0, 10.0, [["flap", 1.4]]], ["flap", ["penguin_shore_a", "penguin_shore_b"], 1.4, 2.0, 3.0, 14.0, []],
			["swim", ["penguin_swim_a", "penguin_swim_b"], 3.0, 5.0, 8.0, 8.0, [["dive", 2.0], ["surface", 1.6]]], ["dive", ["penguin_swim_a", "penguin_swim_b"], 1.5, 2.4, 2.4, 20.0, [["surface", 1.6]]],
			["slide", ["penguin_slide_top"], 1.0, 0.0, 0.0, 50.0, []]],
		"treat": ["eat", "penguin_shore_b", 3.2], "emotes": {"wave": ["flap", 2.0], "cheer": ["hop", 1.8], "heart": ["blink", 2.4], "dance": ["waddle", 2.6]}},
}

## Toys of the zoo toy box (section 10.4): toy kind -> species -> [action, seconds].
## An animal whose habitat holds a toy goes to it now and then and plays with it this way.
const TOY_ANSWERS := {
	"zoo_ball": {"lion": ["pounce", 1.4], "lioness": ["pounce", 1.4], "tiger": ["hug_kick", 3.0], "otter": ["push_ball", 3.0], "monkey": ["play_ball", 3.2], "panda": ["play_ball", 3.2], "penguin": ["hop", 2.4]},
	"zoo_box": {"lion": ["sit_on", 5.0], "lioness": ["sit_on", 5.0], "tiger": ["hide", 6.0], "monkey": ["peek", 2.8], "penguin": ["hop", 2.0]},
	"scratching_log": {"lion": ["scratch_log", 3.0], "lioness": ["scratch_log", 3.0], "tiger": ["scratch_log", 3.0], "otter": ["slide", 0.0], "elephant": ["dust", 3.0]},
	"leaf_feeder": {"giraffe": ["browse", 6.0], "zebra": ["graze", 5.0], "panda": ["munch", 6.0], "elephant": ["eat", 5.0]},
	"hay_bale": {"zebra": ["eat", 4.0], "monkey": ["sit_dangle", 4.0], "elephant": ["eat", 5.0]},
	"play_mirror": {"monkey": ["faces", 3.0], "lion": ["puzzled", 2.6], "lioness": ["puzzled", 2.6], "tiger": ["pat", 2.6], "panda": ["look", 2.6], "elephant": ["look", 2.6], "penguin": ["preen", 3.0]},
	"garden_umbrella": {"lion": ["bask", 8.0], "lioness": ["nap", 8.0], "panda": ["nap", 8.0], "penguin": ["preen", 5.0]},
}
## How often a free animal goes to a toy instead of its routine, when one is in its habitat.
const TOY_CHANCE := 0.45

## Answers a child can find (the discovery log, section 10.6): species -> answer key -> the hint for
## a child who has not seen it yet. Keys are what the brain reports in its "found" events.
const ANSWERS := {
	"lion": {"roar": "Try cheering near Rory.", "pace": "Walk along Lion's Pass.", "treat": "Offer a treat at the overlook.", "ball": "Put a ball on Lion Hill."},
	"lioness": {"roll": "Try dancing near Honey.", "treat": "Offer a treat at the overlook."},
	"tiger": {"peekaboo": "Stand very still by the bamboo.", "pool_leap": "Float a ball in the tiger pool.", "show_walk": "Cheer for Tango.", "treat": "Offer Tango a treat."},
	"monkey": {"copy": "Try a dance near the monkeys.", "rings": "Walk up Canopy Lane.", "bell": "Ring the bell.", "tyre": "Push the tyre swing.", "drums": "Play the drums.", "catch": "Offer a banana."},
	"giraffe": {"bow": "Try standing very still near Topper.", "treat": "Offer a treat at the gate.", "drink": "Pump some water."},
	"zebra": {"gallop": "Run along the meadow near the zebras.", "buck": "Cheer for the zebras.", "treat": "Offer a treat at the gate."},
	"hippo": {"surface": "Stand still on the jetty.", "chomp": "Offer Bubbles a treat.", "shower": "Turn on the shower."},
	"otter": {"escort": "Walk along the bank.", "fetch": "Put a ball on the beach.", "treat": "Offer a treat on the beach."},
	"panda": {"sit_up": "Stand very still at the Bamboo Grove gate.", "treat": "Offer Bao a treat.", "ball": "Put a ball in the Bamboo Grove."},
	"elephant": {"trumpet": "Cheer by the Savanna gate.", "spray": "Pump some water at the waterhole.", "treat": "Offer Mabel a treat."},
	"penguin": {"waddle": "Run along the beach at Splash Bay.", "treat": "Offer Pebble or Flip a treat."},
}

## The line over an animal busy with a child (untranslated, %s = its name).
const LINES := {
	"roar": "%s says hello!", "pace": "%s is walking with you.", "eat": "%s loves the treat.", "peekaboo": "%s is playing peekaboo.",
	"pool_leap": "%s is fetching the ball.", "copy": "%s is copying you!", "bell": "%s rang the bell!", "bow": "%s bows to say hello.",
	"gallop": "%s is running with you!", "surface": "%s came to see you.", "escort": "%s is swimming with you.", "full": "%s is full and happy.",
	"rings": "%s is swinging beside you.", "drums": "%s is drumming!", "tyre": "%s is swinging high!", "fetch": "%s brings the ball back.",
	"show_walk": "%s is showing off!", "sit_up": "%s sits up to say hello!", "trumpet": "%s trumpets hello!",
	"spray": "%s is spraying water!", "waddle": "%s is waddling with you!",
}

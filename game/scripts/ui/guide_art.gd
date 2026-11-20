## Small illustrated scenes for the activity guide, drawn as SVG in code in the
## same soft style as the HUD icons (no image files, no reference artwork).
## Each scene shows how its activity is played, not just a symbol.
extends RefCounted

const W := 160
const H := 110

const SCENES := {
	# A: a pig with a wish bubble showing a bench by a pond.
	"wishes": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/>"
		+ "<ellipse cx='48' cy='80' rx='26' ry='18' fill='#f2b6c0'/><circle cx='68' cy='70' r='13' fill='#f2b6c0'/><ellipse cx='76' cy='73' rx='6' ry='4.5' fill='#e48d9d'/>"
		+ "<circle cx='74' cy='73' r='1.4' fill='#7a4a52'/><circle cx='78' cy='73' r='1.4' fill='#7a4a52'/><circle cx='66' cy='66' r='2' fill='#344d40'/>"
		+ "<path d='M58 58 L62 50 L66 58 Z' fill='#e48d9d'/><rect x='34' y='92' width='6' height='10' rx='3' fill='#e48d9d'/><rect x='54' y='92' width='6' height='10' rx='3' fill='#e48d9d'/>"
		+ "<circle cx='88' cy='54' r='3' fill='#fffdf6'/><circle cx='95' cy='46' r='4.5' fill='#fffdf6'/>"
		+ "<rect x='96' y='8' width='58' height='40' rx='14' fill='#fffdf6'/><ellipse cx='136' cy='36' rx='13' ry='6' fill='#86c3e6'/>"
		+ "<rect x='104' y='22' width='22' height='5' rx='2' fill='#b98a5e'/><rect x='104' y='29' width='22' height='4' rx='2' fill='#b98a5e'/>"
		+ "<rect x='106' y='33' width='3' height='8' fill='#8a6444'/><rect x='121' y='33' width='3' height='8' fill='#8a6444'/>",
	# B: a tree stump, the golden acorn and the warmth dots (two of four warm).
	"acorn": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/>"
		+ "<path d='M14 92 Q40 70 62 84 T110 76' fill='none' stroke='#b8a98c' stroke-width='3' stroke-dasharray='5 6'/>"
		+ "<ellipse cx='46' cy='84' rx='24' ry='8' fill='#8a6444'/><rect x='22' y='62' width='48' height='22' fill='#a77c55'/><ellipse cx='46' cy='62' rx='24' ry='8' fill='#d9b48a'/>"
		+ "<ellipse cx='46' cy='62' rx='12' ry='4' fill='none' stroke='#a77c55' stroke-width='2'/>"
		+ "<circle cx='120' cy='76' r='22' fill='#f6d55c' opacity='0.35'/><ellipse cx='120' cy='80' rx='11' ry='13' fill='#e8b33c'/><path d='M107 72 Q120 58 133 72 Z' fill='#8a6444'/><rect x='118' y='60' width='3' height='7' rx='1.5' fill='#8a6444'/>"
		+ "<rect x='54' y='10' width='76' height='24' rx='12' fill='#fffdf6'/>"
		+ "<circle cx='70' cy='22' r='6' fill='#e9806e'/><circle cx='86' cy='22' r='6' fill='#e9806e'/><circle cx='102' cy='22' r='6' fill='#e5eddc' stroke='#a3b29f' stroke-width='2'/><circle cx='118' cy='22' r='6' fill='#e5eddc' stroke='#a3b29f' stroke-width='2'/>",
	# C: a wrapped present, an arrow, and the chair it turns back into.
	"gifts": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/>"
		+ "<rect x='16' y='50' width='50' height='44' rx='6' fill='#ec8fa3'/><rect x='12' y='42' width='58' height='14' rx='5' fill='#f2b6c0'/>"
		+ "<rect x='36' y='42' width='10' height='52' fill='#f6d55c'/><path d='M41 42 C26 26 18 40 41 42 C64 40 56 26 41 42 Z' fill='#f6d55c' stroke='#e8b33c' stroke-width='2'/>"
		+ "<path d='M78 70 L100 70' stroke='#557c5e' stroke-width='6' stroke-linecap='round'/><path d='M96 60 L108 70 L96 80 Z' fill='#557c5e'/>"
		+ "<rect x='118' y='34' width='6' height='58' rx='3' fill='#b98a5e'/><rect x='118' y='62' width='30' height='8' rx='3' fill='#d9b48a'/>"
		+ "<rect x='120' y='70' width='5' height='22' rx='2' fill='#b98a5e'/><rect x='141' y='70' width='5' height='22' rx='2' fill='#b98a5e'/>"
		+ "<rect x='120' y='56' width='26' height='7' rx='3' fill='#fffdf6'/>",
	# D: one garden bed growing in four steps, with a watering can.
	"garden": "<rect width='160' height='110' rx='16' fill='#e5eddc'/>"
		+ "<rect x='8' y='70' width='144' height='22' rx='6' fill='#8a6444'/><rect x='12' y='66' width='136' height='8' rx='4' fill='#6b4e36'/>"
		+ "<circle cx='28' cy='66' r='3' fill='#d9b48a'/><circle cx='34' cy='67' r='2.5' fill='#d9b48a'/>"
		+ "<path d='M62 66 L62 54' stroke='#6aa760' stroke-width='3'/><ellipse cx='57' cy='54' rx='5' ry='3' fill='#95c97f'/><ellipse cx='67' cy='52' rx='5' ry='3' fill='#95c97f'/>"
		+ "<path d='M98 66 L98 42' stroke='#6aa760' stroke-width='3'/><ellipse cx='92' cy='54' rx='5' ry='3' fill='#95c97f'/><ellipse cx='98' cy='40' rx='5' ry='7' fill='#ec8fa3'/>"
		+ "<path d='M134 66 L134 38' stroke='#6aa760' stroke-width='3'/><ellipse cx='128' cy='52' rx='5' ry='3' fill='#95c97f'/>"
		+ "<circle cx='134' cy='32' r='5' fill='#f6d55c'/><circle cx='127' cy='32' r='5' fill='#ec8fa3'/><circle cx='141' cy='32' r='5' fill='#ec8fa3'/><circle cx='134' cy='25' r='5' fill='#ec8fa3'/><circle cx='134' cy='39' r='5' fill='#ec8fa3'/><circle cx='134' cy='32' r='3.5' fill='#f6d55c'/>"
		+ "<path d='M44 60 L52 60 M80 56 L88 56 M116 52 L124 52' stroke='#557c5e' stroke-width='3' stroke-linecap='round'/>"
		+ "<rect x='14' y='14' width='30' height='22' rx='6' fill='#86c3e6'/><path d='M44 22 L64 12' stroke='#86c3e6' stroke-width='5' stroke-linecap='round'/><path d='M14 18 Q4 24 14 32' fill='none' stroke='#5c9fc4' stroke-width='3'/>"
		+ "<circle cx='68' cy='18' r='2' fill='#86c3e6'/><circle cx='72' cy='24' r='2' fill='#86c3e6'/><circle cx='66' cy='26' r='2' fill='#86c3e6'/>",
	# E: the drum, music notes, twinkling lanterns and a dancing child.
	"party": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/>"
		+ "<path d='M10 14 Q80 34 150 14' fill='none' stroke='#6b5a48' stroke-width='2'/>"
		+ "<rect x='30' y='20' width='12' height='15' rx='5' fill='#f6d55c'/><rect x='74' y='26' width='12' height='15' rx='5' fill='#ec8fa3'/><rect x='118' y='20' width='12' height='15' rx='5' fill='#86c3e6'/>"
		+ "<path d='M26 18 L22 14 M46 18 L50 14 M70 24 L66 20 M90 24 L94 20 M114 18 L110 14 M134 18 L138 14' stroke='#e8b33c' stroke-width='2' stroke-linecap='round'/>"
		+ "<ellipse cx='46' cy='66' rx='26' ry='8' fill='#f3ead8'/><rect x='20' y='66' width='52' height='26' fill='#e9806e'/><ellipse cx='46' cy='92' rx='26' ry='8' fill='#c9604f'/><ellipse cx='46' cy='66' rx='26' ry='8' fill='#f3ead8' stroke='#c9604f' stroke-width='2'/>"
		+ "<path d='M22 70 L34 90 L46 70 L58 90 L70 70' fill='none' stroke='#f6d55c' stroke-width='2'/>"
		+ "<path d='M60 44 L60 30 L70 27 L70 41' fill='none' stroke='#557c5e' stroke-width='3'/><circle cx='57' cy='45' r='4' fill='#557c5e'/><circle cx='67' cy='42' r='4' fill='#557c5e'/>"
		+ "<circle cx='118' cy='50' r='8' fill='#5b4636'/><rect x='111' y='58' width='14' height='18' rx='6' fill='#f2cf6b'/>"
		+ "<path d='M111 62 L100 52 M125 62 L136 50 M114 76 L108 92 M122 76 L130 90' stroke='#5b4636' stroke-width='4' stroke-linecap='round'/>",
	# F: a cottage, a heart sticker and the open guest book.
	"visits": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/>"
		+ "<path d='M14 50 L50 18 L86 50 Z' fill='#d98b6a'/><rect x='22' y='48' width='56' height='46' fill='#f5ead6'/>"
		+ "<rect x='42' y='66' width='16' height='28' rx='3' fill='#86c3e6'/><rect x='28' y='56' width='10' height='10' rx='2' fill='#bfe3f0'/><rect x='62' y='56' width='10' height='10' rx='2' fill='#bfe3f0'/>"
		+ "<path d='M112 34 C112 26 100 24 100 34 C100 42 112 48 112 52 C112 48 124 42 124 34 C124 24 112 26 112 34 Z' fill='#e9806e'/>"
		+ "<path d='M96 74 Q114 66 132 74 L132 96 Q114 88 96 96 Z' fill='#fffdf6' stroke='#b98a5e' stroke-width='2'/><path d='M132 74 Q150 66 150 66 L150 88 Q140 88 132 96' fill='#fffdf6' stroke='#b98a5e' stroke-width='2'/>"
		+ "<path d='M102 78 L124 76 M102 84 L120 82 M138 76 L146 74 M138 82 L146 80' stroke='#a3b29f' stroke-width='2' stroke-linecap='round'/>",
	# G: the photo ideas board with two checks, and the camera.
	"photos": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/>"
		+ "<rect x='16' y='14' width='72' height='58' rx='5' fill='#d9b48a'/><rect x='20' y='18' width='64' height='50' rx='3' fill='#fffdf6'/>"
		+ "<rect x='24' y='22' width='26' height='19' rx='3' fill='#86c3e6'/><rect x='54' y='22' width='26' height='19' rx='3' fill='#e9806e'/>"
		+ "<rect x='24' y='45' width='26' height='19' rx='3' fill='#95c97f'/><rect x='54' y='45' width='26' height='19' rx='3' fill='#c9b6e4'/>"
		+ "<circle cx='46' cy='26' r='6' fill='#557c5e'/><path d='M43 26 L45.5 28.5 L49.5 23.5' fill='none' stroke='#fffdf6' stroke-width='2' stroke-linecap='round'/>"
		+ "<circle cx='76' cy='49' r='6' fill='#557c5e'/><path d='M73 49 L75.5 51.5 L79.5 46.5' fill='none' stroke='#fffdf6' stroke-width='2' stroke-linecap='round'/>"
		+ "<rect x='30' y='72' width='6' height='24' fill='#b98a5e'/><rect x='68' y='72' width='6' height='24' fill='#b98a5e'/>"
		+ "<rect x='100' y='40' width='48' height='34' rx='8' fill='#344d40'/><rect x='110' y='34' width='16' height='8' rx='3' fill='#344d40'/>"
		+ "<circle cx='124' cy='57' r='11' fill='#86c3e6' stroke='#fffdf6' stroke-width='3'/><circle cx='140' cy='46' r='3' fill='#f6d55c'/>",
	# H: the weather vane over four weathers: sun, rain, autumn leaf, snow.
	"weather": "<rect width='160' height='110' rx='16' fill='#e5eddc'/>"
		+ "<rect x='8' y='8' width='34' height='34' rx='8' fill='#fff1c4'/><circle cx='25' cy='25' r='8' fill='#f6d55c'/>"
		+ "<rect x='118' y='8' width='34' height='34' rx='8' fill='#dbe9f2'/><ellipse cx='135' cy='20' rx='11' ry='6' fill='#fffdf6'/>"
		+ "<path d='M128 30 L126 36 M135 30 L133 36 M142 30 L140 36' stroke='#5c9fc4' stroke-width='2.5' stroke-linecap='round'/>"
		+ "<rect x='8' y='66' width='34' height='34' rx='8' fill='#f6e2c8'/><path d='M25 72 C35 78 35 90 25 94 C15 90 15 78 25 72 Z' fill='#e08a3c'/><path d='M25 74 L25 94' stroke='#a85a22' stroke-width='1.5'/>"
		+ "<rect x='118' y='66' width='34' height='34' rx='8' fill='#eef4f8'/>"
		+ "<path d='M135 72 L135 94 M125 77 L145 89 M125 89 L145 77' stroke='#86c3e6' stroke-width='2.5' stroke-linecap='round'/>"
		+ "<rect x='77' y='34' width='6' height='66' rx='3' fill='#557c5e'/><ellipse cx='80' cy='100' rx='18' ry='4' fill='#cfe0bf'/>"
		+ "<path d='M54 34 L100 34' stroke='#557c5e' stroke-width='4' stroke-linecap='round'/><path d='M100 26 L112 34 L100 42 Z' fill='#e9806e'/>"
		+ "<path d='M54 28 L48 34 L54 40 L60 34 Z' fill='#86c3e6'/><circle cx='80' cy='26' r='5' fill='#f6d55c'/>",
	# I: the zoo tram on its rail, a lion with a mane and a monkey on a branch.
	"zoo": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/>"
		+ "<rect x='8' y='86' width='144' height='4' rx='2' fill='#8d8f96'/><path d='M16 90 L16 94 M40 90 L40 94 M64 90 L64 94 M88 90 L88 94 M112 90 L112 94 M136 90 L136 94' stroke='#a8714a' stroke-width='3'/>"
		+ "<rect x='12' y='56' width='60' height='30' rx='8' fill='#e9806e'/><rect x='12' y='72' width='60' height='6' fill='#fffdf6'/>"
		+ "<rect x='18' y='62' width='13' height='10' rx='3' fill='#bfe3f0'/><rect x='35' y='62' width='13' height='10' rx='3' fill='#bfe3f0'/><rect x='52' y='62' width='13' height='10' rx='3' fill='#bfe3f0'/>"
		+ "<rect x='22' y='50' width='40' height='8' rx='4' fill='#c9604f'/><circle cx='26' cy='88' r='5' fill='#6b5a48'/><circle cx='58' cy='88' r='5' fill='#6b5a48'/>"
		+ "<circle cx='104' cy='56' r='24' fill='#c98a3c'/><circle cx='104' cy='58' r='15' fill='#f2c46a'/>"
		+ "<circle cx='93' cy='44' r='5' fill='#f2c46a'/><circle cx='115' cy='44' r='5' fill='#f2c46a'/><ellipse cx='104' cy='64' rx='7' ry='5' fill='#fffdf6'/>"
		+ "<circle cx='98' cy='55' r='2' fill='#344d40'/><circle cx='110' cy='55' r='2' fill='#344d40'/><path d='M101 61 L107 61 L104 65 Z' fill='#7a4a52'/>"
		+ "<rect x='96' y='78' width='16' height='10' rx='5' fill='#f2c46a'/>"
		+ "<path d='M120 26 Q140 20 156 28' fill='none' stroke='#8a6444' stroke-width='5' stroke-linecap='round'/><ellipse cx='142' cy='34' rx='7' ry='9' fill='#a77c55'/>"
		+ "<circle cx='142' cy='22' r='7' fill='#a77c55'/><circle cx='142' cy='24' r='4.5' fill='#e8c9a0'/><circle cx='135' cy='20' r='3' fill='#a77c55'/><circle cx='149' cy='20' r='3' fill='#a77c55'/>"
		+ "<circle cx='140' cy='22' r='1.2' fill='#344d40'/><circle cx='144' cy='22' r='1.2' fill='#344d40'/><path d='M149 38 Q158 44 152 52' fill='none' stroke='#a77c55' stroke-width='3' stroke-linecap='round'/>",
}

## Things to build and try (activity_guide.gd MAKE): one small scene each, in the same style.
const MAKE_SCENES := {
	"contraptions": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/><rect x='14' y='78' width='30' height='14' rx='4' fill='#d9a466'/><ellipse cx='29' cy='76' rx='11' ry='7' fill='#e9806e'/><path d='M48 70 L60 70 M66 70 L78 70' stroke='#f2a541' stroke-width='4' stroke-linecap='round' stroke-dasharray='2 8'/><path d='M78 64 L88 70 L78 76 Z' fill='#f2a541'/><rect x='92' y='34' width='5' height='60' rx='2' fill='#6b5a48'/><rect x='84' y='20' width='21' height='18' rx='6' fill='#f6d55c'/><circle cx='94' cy='29' r='16' fill='#f6d55c' opacity='0.3'/><path d='M108 60 L118 60' stroke='#f2a541' stroke-width='4' stroke-linecap='round' stroke-dasharray='2 8'/><rect x='136' y='50' width='3' height='44' fill='#fffdf6'/><path d='M137 50 L150 40 L137 44 Z M137 50 L124 60 L137 56 Z M137 50 L147 63 L141 50 Z M137 50 L127 37 L133 50 Z' fill='#ec8fa3'/><circle cx='137' cy='50' r='3' fill='#f6d55c'/>",
	"puzzles": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/><rect x='14' y='60' width='50' height='32' rx='5' fill='#d9a466'/><path d='M14 62 Q39 40 64 62 Z' fill='#f2cf6b'/><rect x='34' y='58' width='10' height='12' rx='2' fill='#f6d55c' stroke='#344d40' stroke-width='2'/><circle cx='26' cy='84' r='3.5' fill='#f6d55c'/><circle cx='38' cy='84' r='3.5' fill='#8a8580'/><circle cx='84' cy='30' r='8' fill='none' stroke='#e8b33c' stroke-width='5'/><path d='M84 38 L84 60 M84 50 L92 50 M84 57 L90 57' stroke='#e8b33c' stroke-width='5' stroke-linecap='round'/><rect x='112' y='20' width='36' height='32' rx='5' fill='#b7a2e0'/><rect x='117' y='26' width='26' height='22' rx='3' fill='#fffdf6'/><path d='M130 29 L139 45 L121 45 Z' fill='#3d5a50'/><rect x='128' y='52' width='4' height='40' fill='#8a6444'/><rect x='96' y='66' width='26' height='24' rx='4' fill='#b7a2e0'/><rect x='100' y='70' width='18' height='16' rx='2' fill='#fffdf6'/><path d='M109 72 L115 83 L103 83 Z' fill='#3d5a50'/>",
	"rides": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/><ellipse cx='80' cy='70' rx='60' ry='24' fill='none' stroke='#8d8f96' stroke-width='10'/><ellipse cx='80' cy='70' rx='60' ry='24' fill='none' stroke='#a8714a' stroke-width='10' stroke-dasharray='3 11'/><ellipse cx='80' cy='70' rx='60' ry='24' fill='none' stroke='#e5eddc' stroke-width='4'/><rect x='58' y='78' width='36' height='18' rx='5' fill='#f4ad8a'/><circle cx='66' cy='97' r='5' fill='#6b5a48'/><circle cx='86' cy='97' r='5' fill='#6b5a48'/><circle cx='76' cy='68' r='8' fill='#5b4636'/><rect x='69' y='74' width='14' height='10' rx='4' fill='#f2cf6b'/><rect x='22' y='20' width='4' height='34' fill='#8a6444'/><path d='M26 20 L44 26 L26 32 Z' fill='#f4ad8a'/><path d='M104 86 L120 86' stroke='#557c5e' stroke-width='5' stroke-linecap='round'/><path d='M118 79 L128 86 L118 93 Z' fill='#557c5e'/>",
	"evening": "<rect width='160' height='110' rx='16' fill='#4a5886'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#5e7a62'/><circle cx='132' cy='24' r='10' fill='#fdf3c8'/><circle cx='136' cy='21' r='9' fill='#4a5886'/><rect x='38' y='44' width='5' height='52' rx='2' fill='#2f3a55'/><rect x='30' y='28' width='21' height='18' rx='6' fill='#f6d55c'/><circle cx='40' cy='37' r='20' fill='#f6d55c' opacity='0.28'/><rect x='108' y='50' width='5' height='46' rx='2' fill='#2f3a55'/><rect x='100' y='34' width='21' height='18' rx='6' fill='#f6d55c'/><circle cx='110' cy='43' r='20' fill='#f6d55c' opacity='0.28'/><circle cx='62' cy='30' r='2.5' fill='#fff3a8'/><circle cx='74' cy='48' r='2.5' fill='#fff3a8'/><circle cx='88' cy='26' r='2.5' fill='#fff3a8'/><circle cx='22' cy='58' r='2.5' fill='#fff3a8'/><circle cx='134' cy='62' r='2.5' fill='#fff3a8'/><circle cx='84' cy='66' r='2.5' fill='#fff3a8'/><circle cx='72' cy='78' r='7' fill='#5b4636'/><rect x='66' y='84' width='12' height='14' rx='5' fill='#f2cf6b'/><path d='M78 88 L88 80' stroke='#5b4636' stroke-width='4' stroke-linecap='round'/>",
	"board": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/><rect x='36' y='14' width='70' height='70' rx='6' fill='#a87a5c'/><rect x='41' y='19' width='60' height='60' rx='3' fill='#fffdf6'/><rect x='56' y='26' width='7' height='7' fill='#ec8fa3'/><rect x='78' y='26' width='7' height='7' fill='#ec8fa3'/><rect x='48' y='34' width='7' height='7' fill='#ec8fa3'/><rect x='56' y='34' width='7' height='7' fill='#ec8fa3'/><rect x='63' y='34' width='7' height='7' fill='#ec8fa3'/><rect x='71' y='34' width='7' height='7' fill='#ec8fa3'/><rect x='78' y='34' width='7' height='7' fill='#ec8fa3'/><rect x='86' y='34' width='7' height='7' fill='#ec8fa3'/><rect x='48' y='41' width='7' height='7' fill='#ec8fa3'/><rect x='56' y='41' width='7' height='7' fill='#ec8fa3'/><rect x='63' y='41' width='7' height='7' fill='#ec8fa3'/><rect x='71' y='41' width='7' height='7' fill='#ec8fa3'/><rect x='78' y='41' width='7' height='7' fill='#ec8fa3'/><rect x='86' y='41' width='7' height='7' fill='#ec8fa3'/><rect x='56' y='49' width='7' height='7' fill='#ec8fa3'/><rect x='63' y='49' width='7' height='7' fill='#ec8fa3'/><rect x='71' y='49' width='7' height='7' fill='#ec8fa3'/><rect x='78' y='49' width='7' height='7' fill='#ec8fa3'/><rect x='63' y='56' width='7' height='7' fill='#ec8fa3'/><rect x='71' y='56' width='7' height='7' fill='#ec8fa3'/><rect x='41' y='71' width='7' height='7' fill='#95c97f'/><rect x='48' y='71' width='7' height='7' fill='#95c97f'/><rect x='56' y='71' width='7' height='7' fill='#95c97f'/><rect x='63' y='71' width='7' height='7' fill='#95c97f'/><rect x='71' y='71' width='7' height='7' fill='#95c97f'/><rect x='78' y='71' width='7' height='7' fill='#95c97f'/><rect x='86' y='71' width='7' height='7' fill='#95c97f'/><rect x='93' y='71' width='7' height='7' fill='#95c97f'/><rect x='48' y='84' width='5' height='14' fill='#8a6444'/><rect x='89' y='84' width='5' height='14' fill='#8a6444'/><circle cx='126' cy='30' r='8' fill='#f2cf6b'/><circle cx='144' cy='30' r='8' fill='#86c3e6'/><circle cx='126' cy='50' r='8' fill='#95c97f'/><circle cx='144' cy='50' r='8' fill='#ec8fa3' stroke='#344d40' stroke-width='3'/>",
	"hello": "<rect width='160' height='110' rx='16' fill='#e5eddc'/><ellipse cx='80' cy='100' rx='74' ry='12' fill='#cfe0bf'/><circle cx='52' cy='40' r='13' fill='#5b4636' opacity='0.45'/><rect x='40' y='52' width='24' height='30' rx='9' fill='#86c3e6' opacity='0.45'/><path d='M64 58 L80 40 M40 60 L30 72 M46 82 L44 96 M58 82 L60 96' stroke='#5b4636' stroke-width='5' stroke-linecap='round' opacity='0.45'/><rect x='78' y='10' width='70' height='26' rx='13' fill='#fffdf6'/><path d='M92 30 L88 42 L102 34 Z' fill='#fffdf6'/><path d='M92 24 L92 17 M96 24 L96 15 M100 24 L100 17 M90 24 Q96 32 102 24' stroke='#557c5e' stroke-width='2.5' fill='none' stroke-linecap='round'/><path d='M110 28 L113 18 L116 28 M108 21 L118 21' stroke='#e8b33c' stroke-width='2.5' fill='none' stroke-linecap='round'/><path d='M132 20 C132 15 125 14 125 20 C125 25 132 28 132 30 C132 28 139 25 139 20 C139 14 132 15 132 20 Z' fill='#e9806e'/><circle cx='118' cy='62' r='11' fill='#3a2a22'/><rect x='108' y='72' width='20' height='24' rx='8' fill='#f2cf6b'/><path d='M108 78 L96 68' stroke='#3a2a22' stroke-width='5' stroke-linecap='round'/>",
}

static var _cache := {}


static func texture(id: String, scale := 2.0) -> Texture2D:
	var key := "%s|%.2f" % [id, scale]
	if _cache.has(key):
		return _cache[key]
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 %d %d'>%s</svg>" % [W, H, W, H, SCENES.get(id, MAKE_SCENES.get(id, ""))]
	var img := Image.new()
	img.load_svg_from_string(svg, scale)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

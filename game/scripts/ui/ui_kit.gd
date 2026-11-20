## UI building blocks: the project theme, SVG icons and helper constructors.
##
## Design values follow docs/design-spec.md: paper #f5f1e7, panel #fffdf6,
## text #344d40, accent #557c5e, soft green #e5eddc, warm yellow #edcf81,
## 24 px panel corners, 16 px button corners and large touch targets.
extends RefCounted

const PAPER := Color("#f5f1e7")
const PANEL := Color("#fffdf6")
const TEXT := Color("#344d40")
const MUTED := Color("#69796a")
const ACCENT := Color("#557c5e")
const SOFT := Color("#e5eddc")
const YELLOW := Color("#edcf81")
const CORAL := Color("#e9806e")
const TOUCH := 76

static var _theme: Theme
## Simulated safe-area insets for layout tests (--safe-insets=l,t,r,b); zero on devices.
static var test_insets := Vector4.ZERO
static var _icons := {}

const ICONS := {
	"sun": "<circle cx='32' cy='32' r='11' fill='#ffcf4a'/><g stroke='#f2a93b' stroke-width='5' stroke-linecap='round'><path d='M32 6 V14 M32 50 V58 M6 32 H14 M50 32 H58 M13.6 13.6 L19.3 19.3 M44.7 44.7 L50.4 50.4 M13.6 50.4 L19.3 44.7 M44.7 19.3 L50.4 13.6'/></g>",
	"rain": "<path d='M18 36 C10 36 8 26 15 23 C15 14 26 11 31 17 C35 10 48 12 48 22 C55 23 56 36 47 36 Z' fill='#cfe3f5' stroke='#5c7fa3' stroke-width='3'/><g stroke='#4f9fe8' stroke-width='4' stroke-linecap='round'><path d='M22 44 L19 52 M33 44 L30 52 M44 44 L41 52'/></g>",
	"moon": "<path d='M40 8 C26 10 16 22 18 36 C20 50 34 58 48 54 C38 50 32 40 33 29 C34 19 39 12 40 8 Z' fill='#ffe28a' stroke='#c99a2e' stroke-width='3'/><circle cx='48' cy='18' r='2.5' fill='#ffe28a'/><circle cx='52' cy='30' r='1.8' fill='#ffe28a'/>",
	"sunset": "<path d='M14 40 A18 18 0 0 1 50 40 Z' fill='#ffb27a' stroke='#e0864a' stroke-width='3'/><g stroke='#e0864a' stroke-width='4' stroke-linecap='round'><path d='M32 10 V16 M12 22 L16 26 M52 22 L48 26'/></g><path d='M6 44 H58 M14 52 H50' stroke='#5c7fa3' stroke-width='4' stroke-linecap='round'/>",
	"auto": "<path d='M48 22 A18 18 0 1 0 50 36' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M42 10 L54 22 L40 28 Z' fill='#344d40'/>",
	"look": "<path d='M6 32 C16 16 48 16 58 32 C48 48 16 48 6 32 Z' fill='#fffdf6' stroke='#344d40' stroke-width='4'/><circle cx='32' cy='32' r='10' fill='#5aaef5'/><circle cx='32' cy='32' r='4.5' fill='#344d40'/><circle cx='35' cy='29' r='2' fill='#fffdf6'/>",
	"pause": "<rect x='16' y='12' width='11' height='40' rx='4' fill='#344d40'/><rect x='37' y='12' width='11' height='40' rx='4' fill='#344d40'/>",
	"decorate": "<path d='M14 30 L34 30 L32 52 L16 52 Z' fill='#edcf81'/><rect x='10' y='24' width='28' height='8' rx='4' fill='#557c5e'/><circle cx='42' cy='18' r='9' fill='#ec8fa3'/><circle cx='42' cy='18' r='3.5' fill='#f6d55c'/><path d='M42 27 L42 44' stroke='#557c5e' stroke-width='3.5' stroke-linecap='round'/>",
	"undo": "<path d='M20 22 C34 14 50 22 50 36 C50 48 38 54 28 50' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M10 22 L24 12 L24 32 Z' fill='#344d40'/>",
	"turn": "<path d='M46 30 A16 16 0 1 1 38 16' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M34 6 L48 14 L34 24 Z' fill='#344d40'/>",
	"paint": "<path d='M32 8 C16 8 8 20 8 32 C8 46 20 56 32 56 C36 56 38 52 36 48 C34 44 36 40 42 40 L48 40 C54 40 56 36 56 30 C56 16 46 8 32 8 Z' fill='#f3ead8' stroke='#344d40' stroke-width='3'/><circle cx='22' cy='24' r='5' fill='#ec8fa3'/><circle cx='34' cy='18' r='5' fill='#86c3e6'/><circle cx='45' cy='26' r='5' fill='#95c97f'/><circle cx='20' cy='38' r='5' fill='#f2cf6b'/>",
	"trash": "<rect x='16' y='20' width='32' height='34' rx='6' fill='#e9806e'/><rect x='10' y='12' width='44' height='8' rx='4' fill='#344d40'/><rect x='26' y='6' width='12' height='8' rx='3' fill='#344d40'/>",
	"check": "<path d='M12 34 L26 48 L52 18' fill='none' stroke='#fffdf6' stroke-width='8' stroke-linecap='round' stroke-linejoin='round'/>",
	"close": "<path d='M16 16 L48 48 M48 16 L16 48' stroke='#344d40' stroke-width='7' stroke-linecap='round'/>",
	"tram": "<rect x='10' y='14' width='44' height='30' rx='10' fill='#f2cf6b' stroke='#344d40' stroke-width='3'/><rect x='16' y='20' width='12' height='10' rx='3' fill='#d4ebf4'/><rect x='36' y='20' width='12' height='10' rx='3' fill='#d4ebf4'/><circle cx='20' cy='48' r='5' fill='#344d40'/><circle cx='44' cy='48' r='5' fill='#344d40'/><rect x='6' y='54' width='52' height='4' rx='2' fill='#b98a5e'/>",
	"paw": "<ellipse cx='32' cy='42' rx='13' ry='11' fill='#b98a5e' stroke='#344d40' stroke-width='3'/><circle cx='16' cy='28' r='6' fill='#b98a5e' stroke='#344d40' stroke-width='3'/><circle cx='26' cy='18' r='6' fill='#b98a5e' stroke='#344d40' stroke-width='3'/><circle cx='38' cy='18' r='6' fill='#b98a5e' stroke='#344d40' stroke-width='3'/><circle cx='48' cy='28' r='6' fill='#b98a5e' stroke='#344d40' stroke-width='3'/>",
	"camera": "<rect x='8' y='18' width='48' height='34' rx='8' fill='#344d40'/><rect x='22' y='10' width='20' height='10' rx='4' fill='#344d40'/><circle cx='32' cy='35' r='11' fill='#fffdf6'/><circle cx='32' cy='35' r='6' fill='#86c3e6'/>",
	"book": "<path d='M8 14 C18 10 26 12 32 18 C38 12 46 10 56 14 L56 52 C46 48 38 50 32 56 C26 50 18 48 8 52 Z' fill='#edcf81' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M32 18 L32 56' stroke='#344d40' stroke-width='3'/>",
	"globe": "<circle cx='32' cy='32' r='22' fill='#86c3e6' stroke='#344d40' stroke-width='3'/><path d='M14 26 C22 22 24 30 30 28 C36 26 34 18 42 16 M20 44 C26 40 32 46 38 42 C44 38 48 42 52 40' stroke='#557c5e' stroke-width='4' fill='none' stroke-linecap='round'/>",
	"wave": "<rect x='22' y='16' width='20' height='30' rx='9' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/><path d='M14 14 C10 20 10 26 14 30 M50 14 C54 20 54 26 50 30' stroke='#344d40' stroke-width='3' fill='none' stroke-linecap='round'/><rect x='26' y='42' width='12' height='14' rx='4' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/>",
	"cheer": "<path d='M32 6 L38 24 L56 24 L42 35 L47 54 L32 42 L17 54 L22 35 L8 24 L26 24 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/>",
	"dance": "<path d='M26 46 L26 12 L50 8 L50 40' fill='none' stroke='#344d40' stroke-width='5' stroke-linejoin='round'/><circle cx='20' cy='46' r='8' fill='#b7a2e0' stroke='#344d40' stroke-width='3'/><circle cx='44' cy='42' r='8' fill='#b7a2e0' stroke='#344d40' stroke-width='3'/>",
	"heart": "<path d='M32 54 C10 38 8 26 12 18 C16 10 28 10 32 20 C36 10 48 10 52 18 C56 26 54 38 32 54 Z' fill='#ef6f86' stroke='#344d40' stroke-width='3'/>",
	"rotate_left": "<path d='M18 30 A16 16 0 1 1 26 46' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M8 22 L20 36 L28 20 Z' fill='#344d40'/>",
	"rotate_right": "<path d='M46 30 A16 16 0 1 0 38 46' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><path d='M56 22 L44 36 L36 20 Z' fill='#344d40'/>",
	"zoom": "<circle cx='28' cy='28' r='16' fill='#fffdf6' stroke='#344d40' stroke-width='6'/><path d='M40 40 L54 54' stroke='#344d40' stroke-width='7' stroke-linecap='round'/><path d='M20 28 L36 28 M28 20 L28 36' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
	"door": "<rect x='16' y='8' width='32' height='48' rx='14' fill='#95c97f' stroke='#344d40' stroke-width='3'/><circle cx='40' cy='34' r='3.5' fill='#f2cf6b'/>",
	"sit": "<rect x='12' y='30' width='40' height='8' rx='4' fill='#d9a466' stroke='#344d40' stroke-width='3'/><path d='M16 38 L16 54 M48 38 L48 54 M14 30 L14 10' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
	"stand": "<circle cx='32' cy='14' r='8' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/><path d='M32 22 L32 42 M20 30 L44 30 M32 42 L22 56 M32 42 L42 56' stroke='#344d40' stroke-width='5' stroke-linecap='round'/>",
	"bell": "<path d='M18 44 C18 30 18 14 32 14 C46 14 46 30 46 44 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><rect x='12' y='42' width='40' height='7' rx='3.5' fill='#344d40'/><circle cx='32' cy='54' r='5' fill='#344d40'/><circle cx='32' cy='10' r='4' fill='#344d40'/>",
	"lantern": "<rect x='18' y='16' width='28' height='34' rx='12' fill='#f2cf6b' stroke='#344d40' stroke-width='3'/><rect x='22' y='10' width='20' height='7' rx='3' fill='#344d40'/><rect x='22' y='48' width='20' height='7' rx='3' fill='#344d40'/><path d='M32 4 L32 10' stroke='#344d40' stroke-width='3'/>",
	"friends": "<circle cx='22' cy='22' r='9' fill='#f2c7a5' stroke='#344d40' stroke-width='3'/><circle cx='42' cy='22' r='9' fill='#d9a27c' stroke='#344d40' stroke-width='3'/><rect x='10' y='34' width='24' height='20' rx='10' fill='#86c3e6' stroke='#344d40' stroke-width='3'/><rect x='30' y='34' width='24' height='20' rx='10' fill='#f4ad8a' stroke='#344d40' stroke-width='3'/>",
	"home": "<path d='M8 30 L32 10 L56 30' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/><rect x='16' y='28' width='32' height='26' rx='4' fill='#f3ead8' stroke='#344d40' stroke-width='3'/><rect x='27' y='38' width='10' height='16' rx='4' fill='#e9806e'/>",
	"play": "<path d='M20 12 L52 32 L20 52 Z' fill='#fffdf6' stroke='#fffdf6' stroke-width='4' stroke-linejoin='round'/>",
	"leave": "<rect x='10' y='10' width='26' height='44' rx='6' fill='#f3ead8' stroke='#344d40' stroke-width='3'/><path d='M28 32 L54 32 M44 22 L54 32 L44 42' stroke='#344d40' stroke-width='5' fill='none' stroke-linecap='round' stroke-linejoin='round'/>",
	"saved": "<circle cx='32' cy='32' r='22' fill='#95c97f'/><path d='M20 33 L29 42 L45 24' fill='none' stroke='#fffdf6' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"music": "<circle cx='32' cy='32' r='26' fill='#b7a2e0' stroke='#344d40' stroke-width='3'/><path d='M27 44 L27 18 L45 14 L45 38' fill='none' stroke='#344d40' stroke-width='4' stroke-linejoin='round'/><circle cx='23' cy='44' r='5.5' fill='#344d40'/><circle cx='41' cy='39' r='5.5' fill='#344d40'/>",
	"stairs_up": "<path d='M10 52 L10 42 L22 42 L22 32 L34 32 L34 22 L46 22 L46 12 L56 12 L56 52 Z' fill='#d9a466' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M16 28 L16 12 M10 18 L16 11 L22 18' stroke='#fffdf6' stroke-width='4' fill='none' stroke-linecap='round' stroke-linejoin='round'/>",
	"stairs_down": "<path d='M10 52 L10 42 L22 42 L22 32 L34 32 L34 22 L46 22 L46 12 L56 12 L56 52 Z' fill='#d9a466' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M16 11 L16 27 M10 21 L16 28 L22 21' stroke='#fffdf6' stroke-width='4' fill='none' stroke-linecap='round' stroke-linejoin='round'/>",
	"wish": "<path d='M32 6 C48 6 58 16 58 28 C58 40 48 48 34 48 L22 58 L24 46 C12 43 6 36 6 28 C6 16 16 6 32 6 Z' fill='#fffdf6' stroke='#344d40' stroke-width='3'/><path d='M32 14 L35.5 23 L45 23 L37.5 29 L40 38 L32 32.5 L24 38 L26.5 29 L19 23 L28.5 23 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='2' stroke-linejoin='round'/>",
	"gift": "<rect x='10' y='26' width='44' height='30' rx='5' fill='#ec8fa3' stroke='#344d40' stroke-width='3'/><rect x='6' y='18' width='52' height='10' rx='4' fill='#f4ad8a' stroke='#344d40' stroke-width='3'/><path d='M32 18 L32 56' stroke='#fffdf6' stroke-width='6'/><path d='M32 18 C24 6 14 10 20 18 Z M32 18 C40 6 50 10 44 18 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='2'/>",
	"key": "<circle cx='22' cy='22' r='12' fill='#f2cf6b' stroke='#344d40' stroke-width='3'/><circle cx='22' cy='22' r='4.5' fill='#fffdf6' stroke='#344d40' stroke-width='3'/><path d='M31 31 L53 53 M45 45 L51 39 M38 38 L43 33' stroke='#344d40' stroke-width='6' stroke-linecap='round'/>",
	"acorn": "<ellipse cx='32' cy='38' rx='15' ry='18' fill='#e3b341' stroke='#344d40' stroke-width='3'/><path d='M14 26 C18 14 46 14 50 26 Z' fill='#a8714a' stroke='#344d40' stroke-width='3'/><path d='M32 14 L34 6' stroke='#344d40' stroke-width='4' stroke-linecap='round'/>",
	"drum": "<ellipse cx='32' cy='20' rx='20' ry='8' fill='#fffdf6' stroke='#344d40' stroke-width='3'/><path d='M12 20 L12 44 C12 50 52 50 52 44 L52 20' fill='#ec8fa3' stroke='#344d40' stroke-width='3'/><path d='M40 4 L30 18' stroke='#a8714a' stroke-width='4' stroke-linecap='round'/>",
	"weather": "<circle cx='22' cy='22' r='10' fill='#f2cf6b' stroke='#344d40' stroke-width='3'/><path d='M20 46 C10 46 10 34 20 34 C22 26 36 24 40 32 C50 30 54 46 44 46 Z' fill='#fffdf6' stroke='#344d40' stroke-width='3'/><path d='M24 52 L22 58 M34 52 L32 58 M44 52 L42 58' stroke='#86c3e6' stroke-width='3' stroke-linecap='round'/>",
	"board": "<rect x='8' y='10' width='48' height='36' rx='5' fill='#d9a466' stroke='#344d40' stroke-width='3'/><rect x='14' y='16' width='16' height='11' rx='2' fill='#86c3e6'/><rect x='34' y='16' width='16' height='11' rx='2' fill='#f4ad8a'/><rect x='14' y='30' width='16' height='11' rx='2' fill='#95c97f'/><rect x='34' y='30' width='16' height='11' rx='2' fill='#b7a2e0'/><path d='M20 46 L16 58 M44 46 L48 58' stroke='#344d40' stroke-width='4' stroke-linecap='round'/>",
	"water": "<path d='M32 8 C32 8 16 28 16 38 C16 48 24 54 32 54 C40 54 48 48 48 38 C48 28 32 8 32 8 Z' fill='#86c3e6' stroke='#344d40' stroke-width='3'/>",
	"search": "<circle cx='28' cy='28' r='15' fill='#e5eddc' stroke='#344d40' stroke-width='6'/><path d='M39 39 L53 53' stroke='#344d40' stroke-width='8' stroke-linecap='round'/>",
	"list": "<rect x='8' y='12' width='48' height='12' rx='6' fill='#e5eddc'/><rect x='8' y='28' width='48' height='12' rx='6' fill='#edcf81'/><rect x='8' y='44' width='48' height='12' rx='6' fill='#e5eddc'/><circle cx='15' cy='18' r='3' fill='#557c5e'/><circle cx='15' cy='34' r='3' fill='#557c5e'/><circle cx='15' cy='50' r='3' fill='#557c5e'/>",
	"recent": "<circle cx='32' cy='32' r='22' fill='#e5eddc' stroke='#344d40' stroke-width='6'/><path d='M32 18 L32 33 L42 39' fill='none' stroke='#344d40' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"guide": "<path d='M8 14 Q20 8 32 14 L32 56 Q20 50 8 56 Z' fill='#e5eddc' stroke='#557c5e' stroke-width='3'/><path d='M32 14 Q44 8 56 14 L56 56 Q44 50 32 56 Z' fill='#fffdf6' stroke='#557c5e' stroke-width='3'/><circle cx='20' cy='28' r='5' fill='#ec8fa3'/><path d='M14 42 L26 40' stroke='#86c3e6' stroke-width='4' stroke-linecap='round'/><path d='M39 26 Q39 20 44 20 Q50 20 50 26 Q50 30 44 32 L44 36' fill='none' stroke='#344d40' stroke-width='4' stroke-linecap='round'/><circle cx='44' cy='44' r='2.5' fill='#344d40'/>",
	"cook": "<path d='M22 14 Q18 8 22 4 M32 14 Q28 8 32 4 M42 14 Q38 8 42 4' fill='none' stroke='#a3b29f' stroke-width='3' stroke-linecap='round'/><rect x='10' y='22' width='44' height='28' rx='8' fill='#e9806e'/><rect x='6' y='18' width='52' height='8' rx='4' fill='#c9604f'/><rect x='2' y='30' width='10' height='6' rx='3' fill='#4a4f55'/><rect x='52' y='30' width='10' height='6' rx='3' fill='#4a4f55'/>",
	"pet_cat": "<ellipse cx='32' cy='44' rx='18' ry='13' fill='#f0a35e'/><circle cx='32' cy='26' r='14' fill='#f0a35e'/><path d='M20 18 L22 6 L30 14 Z M44 18 L42 6 L34 14 Z' fill='#d9894a'/><circle cx='27' cy='25' r='2.5' fill='#344d40'/><circle cx='37' cy='25' r='2.5' fill='#344d40'/><circle cx='32' cy='30' r='2' fill='#ec8fa3'/><path d='M50 44 Q60 36 56 26' fill='none' stroke='#f0a35e' stroke-width='5' stroke-linecap='round'/>",
	"pet_dog": "<ellipse cx='32' cy='44' rx='19' ry='13' fill='#b77b4f'/><circle cx='32' cy='26' r='14' fill='#b77b4f'/><ellipse cx='18' cy='26' rx='6' ry='11' fill='#7d5236'/><ellipse cx='46' cy='26' rx='6' ry='11' fill='#7d5236'/><ellipse cx='32' cy='31' rx='7' ry='5' fill='#e8c9a6'/><circle cx='32' cy='29' r='2.5' fill='#344d40'/><circle cx='27' cy='23' r='2.2' fill='#344d40'/><circle cx='37' cy='23' r='2.2' fill='#344d40'/>",
	"pet_bird": "<ellipse cx='30' cy='38' rx='16' ry='13' fill='#6fb2e0'/><circle cx='40' cy='24' r='10' fill='#6fb2e0'/><path d='M49 24 L58 27 L49 30 Z' fill='#f2a33a'/><circle cx='42' cy='22' r='2' fill='#344d40'/><ellipse cx='26' cy='38' rx='10' ry='6' fill='#4f93c4'/><path d='M14 40 L4 46 L14 46 Z' fill='#4f93c4'/><path d='M28 50 L26 58 M34 50 L36 58' stroke='#f2a33a' stroke-width='3' stroke-linecap='round'/>",
	"pet_butterfly": "<ellipse cx='20' cy='24' rx='13' ry='11' fill='#6fa8e6'/><ellipse cx='44' cy='24' rx='13' ry='11' fill='#6fa8e6'/><ellipse cx='22' cy='42' rx='9' ry='8' fill='#ef8fb1'/><ellipse cx='42' cy='42' rx='9' ry='8' fill='#ef8fb1'/><rect x='30' y='16' width='4' height='34' rx='2' fill='#3b2c22'/><path d='M31 16 L26 6 M33 16 L38 6' stroke='#3b2c22' stroke-width='2' stroke-linecap='round'/>",
	"todo": "<circle cx='32' cy='32' r='20' fill='#fffdf6' stroke='#a3b29f' stroke-width='5'/>",
	"bus": "<rect x='8' y='10' width='48' height='38' rx='8' fill='#5aa0d8' stroke='#344d40' stroke-width='3'/><rect x='13' y='16' width='38' height='13' rx='3' fill='#d4ebf4'/><rect x='13' y='34' width='8' height='6' rx='2' fill='#ffe28a'/><rect x='43' y='34' width='8' height='6' rx='2' fill='#ffe28a'/><circle cx='19' cy='51' r='5' fill='#344d40'/><circle cx='45' cy='51' r='5' fill='#344d40'/>",
	"wheel": "<circle cx='32' cy='28' r='20' fill='none' stroke='#e2725b' stroke-width='4'/><g stroke='#344d40' stroke-width='2.5'><path d='M32 8 V48 M12 28 H52 M18 14 L46 42 M46 14 L18 42'/></g><path d='M32 28 L20 58 M32 28 L44 58' stroke='#344d40' stroke-width='4' stroke-linecap='round'/><g fill='#f2cf6b' stroke='#344d40' stroke-width='2'><rect x='27' y='4' width='10' height='8' rx='2'/><rect x='47' y='24' width='10' height='8' rx='2'/><rect x='7' y='24' width='10' height='8' rx='2'/><rect x='27' y='44' width='10' height='8' rx='2'/></g>",
	"snack": "<path d='M30 6 L34 6 L34 58 L30 58 Z' fill='#c9a26b'/><circle cx='32' cy='16' r='8' fill='#e04f5f' stroke='#344d40' stroke-width='2.5'/><circle cx='32' cy='30' r='8' fill='#f29b4a' stroke='#344d40' stroke-width='2.5'/><circle cx='32' cy='44' r='8' fill='#e04f5f' stroke='#344d40' stroke-width='2.5'/>",
	"fireworks": "<g stroke-width='4' stroke-linecap='round'><path d='M32 30 L32 10 M32 30 L50 22 M32 30 L14 22 M32 30 L46 44 M32 30 L18 44' stroke='#e2725b'/><path d='M32 30 L42 12 M32 30 L22 12 M32 30 L52 34 M32 30 L12 34' stroke='#f2cf6b'/></g><circle cx='32' cy='30' r='4' fill='#ffffff' stroke='#344d40' stroke-width='2'/><path d='M32 36 L32 58' stroke='#8a6a4a' stroke-width='3' stroke-dasharray='3 4'/>",
	"fountain": "<path d='M32 34 C32 18 22 12 14 16 M32 34 C32 18 42 12 50 16 M32 34 L32 8' fill='none' stroke='#4f9fe8' stroke-width='4' stroke-linecap='round'/><circle cx='14' cy='18' r='3' fill='#4f9fe8'/><circle cx='50' cy='18' r='3' fill='#4f9fe8'/><circle cx='32' cy='7' r='3' fill='#4f9fe8'/><path d='M8 40 H56 L52 54 H12 Z' fill='#cfe3f5' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/>",
	"warn": "<path d='M32 8 L58 54 L6 54 Z' fill='#f2cf6b' stroke='#344d40' stroke-width='3' stroke-linejoin='round'/><path d='M32 24 L32 38' stroke='#344d40' stroke-width='6' stroke-linecap='round'/><circle cx='32' cy='46' r='3.5' fill='#344d40'/>",
}


## Anchors a control to a screen corner/edge and makes it grow inward from there.
static func pin(c: Control, preset: int) -> void:
	c.set_anchors_and_offsets_preset(preset)
	var right := [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_RIGHT_WIDE]
	var hcenter := [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER, Control.PRESET_VCENTER_WIDE]
	var bottom := [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_WIDE]
	var vcenter := [Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER, Control.PRESET_HCENTER_WIDE]
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset in right else (Control.GROW_DIRECTION_BOTH if preset in hcenter else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset in bottom else (Control.GROW_DIRECTION_BOTH if preset in vcenter else Control.GROW_DIRECTION_END)


## Shrinks a full-screen root control to the device safe area (iPadOS home
## indicator, rounded corners). Desktop windows are left unchanged.
static func fit_safe_area(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if test_insets != Vector4.ZERO:
		# Automated layout tests simulate device insets (left, top, right, bottom) in UI pixels.
		c.offset_left = test_insets.x
		c.offset_top = test_insets.y
		c.offset_right = -test_insets.z
		c.offset_bottom = -test_insets.w
		return
	var tv: bool = preload("res://scripts/core/tv_mode.gd").active()
	if not OS.has_feature("mobile") and not tv:
		return
	if tv:
		# A TV may crop its picture edges (overscan): keep to the title-safe area, or the system's if larger.
		var vs := c.get_viewport().get_visible_rect().size
		var tm = preload("res://scripts/core/tv_mode.gd")
		c.offset_left = vs.x * tm.SAFE_X
		c.offset_right = -vs.x * tm.SAFE_X
		c.offset_top = vs.y * tm.SAFE_Y
		c.offset_bottom = -vs.y * tm.SAFE_Y
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0 or safe.size.x <= 0:
		return
	var k := c.get_viewport().get_visible_rect().size / win
	c.offset_left = maxf(c.offset_left, safe.position.x * k.x) if tv else safe.position.x * k.x
	c.offset_top = maxf(c.offset_top, safe.position.y * k.y) if tv else safe.position.y * k.y
	c.offset_right = minf(c.offset_right, -(win.x - safe.end.x) * k.x) if tv else -(win.x - safe.end.x) * k.x
	c.offset_bottom = minf(c.offset_bottom, -(win.y - safe.end.y) * k.y) if tv else -(win.y - safe.end.y) * k.y


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED.lightened(0.3))
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_color("icon_pressed_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 44)
	t.set_stylebox("normal", "Button", box(PANEL, 16, 2, SOFT.darkened(0.08)))
	t.set_stylebox("hover", "Button", focus_box(16))   # unified r6: the pointer's (and the mouse's) focus ring
	t.set_stylebox("pressed", "Button", box(SOFT, 16, 3, ACCENT))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 16, 3, YELLOW))
	t.set_stylebox("disabled", "Button", box(PANEL.darkened(0.03), 16, 2, SOFT))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 24, 0, Color.TRANSPARENT, 0.12))
	t.set_stylebox("normal", "LineEdit", box(Color.WHITE, 12, 2, SOFT.darkened(0.1)))
	t.set_stylebox("focus", "LineEdit", box(Color.WHITE, 12, 3, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("separation", "VBoxContainer", 12)
	_theme = t
	return t


## unified r6 (Apple TV feedback): one focused state for every action button in every world (the town, Thousand
## Town, the Workshop, the reef): the button under the controller's pointer (or the mouse) gets the theme's yellow
## focus ring over a soft fill; pressed is the theme's soft fill with the accent border. Primary (green) buttons keep
## their green and get the same ring.
const FOCUS_RING := Color("#e2b84f")
const FOCUS_W := 4


static func focus_box(radius := 16, bg := PANEL.lerp(SOFT, 0.5)) -> StyleBoxFlat:
	return box(bg, radius, FOCUS_W, FOCUS_RING)


## unified r6: a destination button (the tram stop's journeys and local trips, a world's way home): one look for all
## of them, the theme's normal / focused / pressed / disabled states, the tram icon, the action row's height and size.
const DEST_H := 88
const DEST_FONT := 26


static func style_destination(b: Button, sized := true) -> void:
	b.add_theme_stylebox_override("normal", box(PANEL, 16, 2, SOFT.darkened(0.08), 0.12))
	b.add_theme_stylebox_override("hover", focus_box(16))
	b.add_theme_stylebox_override("pressed", box(SOFT, 16, 3, ACCENT))
	b.add_theme_stylebox_override("disabled", box(PANEL.darkened(0.03), 16, 2, SOFT))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, TEXT)
	b.icon = icon("tram")
	if sized:   # the compact Ride home beside a map's name keeps its own size
		b.add_theme_font_size_override("font_size", DEST_FONT)
		b.custom_minimum_size.y = DEST_H


## Back to the button's own look (a context button that was a destination at the tram stop and is a door now).
static func unstyle_destination(b: Button, primary: bool, font_size: int) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.remove_theme_color_override(c)
	if primary:
		_primary(b)
	b.add_theme_font_size_override("font_size", font_size)


## unified r6: the controller hints of every world in one form: the same panel, text colour and size, "glyph  action"
## parts four spaces apart, alternative buttons as "B / +" (PadInput's bar in the town and Thousand Town, the
## Workshop's and the reef's own).
const HINT_SIZE := 20
const HINT_SEP := "    "


static func hint_panel() -> PanelContainer:
	var p := panel(14, Color(1, 1, 1, 0.92))
	p.theme = theme()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func hint_label() -> Label:
	var l := label("", HINT_SIZE, TEXT)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # built from translated parts
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func hint_part(glyph: String, action: String) -> String:
	return "%s  %s" % [glyph, action]


static func glyphs(labels: Array) -> String:
	return " / ".join(labels.map(func(x): return str(x)))


static func box(bg: Color, radius := 16, border := 0, border_color := Color.TRANSPARENT, shadow := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	if shadow > 0.0:
		s.shadow_color = Color(0.2, 0.25, 0.2, shadow)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 4)
	return s


static func icon(name: String, size := 64) -> Texture2D:
	var key := "%s|%d" % [name, size]
	if _icons.has(key):
		return _icons[key]
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>%s</svg>" % ICONS.get(name, ICONS["warn"])
	var img := Image.new()
	img.load_svg_from_string(svg, size / 64.0)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


static func button(text: String, icon_name := "", primary := false, min_w := TOUCH) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
	if primary:
		_primary(b)
	return b


static func _primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(ACCENT, 16))
	b.add_theme_stylebox_override("hover", focus_box(16, ACCENT.lightened(0.1)))   # unified r6: the focus ring
	b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.1), 16))
	b.add_theme_stylebox_override("disabled", box(ACCENT.lerp(PAPER, 0.6), 16))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, PANEL)


static func icon_button(icon_name: String, tooltip: String, size := TOUCH) -> Button:
	var b := Button.new()
	b.icon = icon(icon_name)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(size, size)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", box(PANEL, size / 2, 2, SOFT.darkened(0.08), 0.1))
	b.add_theme_stylebox_override("hover", focus_box(size / 2))   # unified r6: the focus ring
	b.add_theme_stylebox_override("pressed", box(SOFT, size / 2, 3, ACCENT))
	return b


static func label(text: String, size := 24, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Fits text broken only at word boundaries (as Label AUTOWRAP_WORD, line spacing 0): the largest of
## sizes giving at most max_lines lines no wider than width. If even the smallest size cannot fit a
## word on a line, the width grows to the widest word (never broken, never clipped).
## Returns {"size", "width", "lines", "height"}.
static func fit_text(font: Font, text: String, width: float, max_lines: int, sizes: Array) -> Dictionary:
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	for s in sizes:
		var r := _measure(font, text, width, s, flags)
		if r["wide"] <= width + 0.5 and r["lines"] <= max_lines:
			return {"size": s, "width": width, "lines": r["lines"], "height": r["lines"] * font.get_height(s)}
	var small: int = sizes[-1]
	var w := width
	while w < width * 3.0:
		w += 4.0
		var r := _measure(font, text, w, small, flags)
		if r["wide"] <= w + 0.5 and r["lines"] <= max_lines:
			return {"size": small, "width": w, "lines": r["lines"], "height": r["lines"] * font.get_height(small)}
	var r := _measure(font, text, w, small, flags)
	return {"size": small, "width": w, "lines": r["lines"], "height": r["lines"] * font.get_height(small)}


static func _measure(font: Font, text: String, width: float, size: int, flags: int) -> Dictionary:
	var para := TextParagraph.new()
	para.break_flags = flags
	para.width = width
	para.add_string(text, font, size)
	var wide := 0.0
	for i in para.get_line_count():
		wide = maxf(wide, para.get_line_width(i))
	return {"lines": para.get_line_count(), "wide": wide}


static func panel(radius := 24, color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, radius, 0, Color.TRANSPARENT, 0.14)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", s)
	return p

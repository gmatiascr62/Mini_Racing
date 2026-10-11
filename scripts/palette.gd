class_name Pal
extends RefCounted
## Commodore 64 inspired palette.

const BLACK := Color("#000000")
const WHITE := Color("#ffffff")
const RED := Color("#883932")
const CYAN := Color("#67b6bd")
const PURPLE := Color("#8b3f96")
const GREEN := Color("#55a049")
const BLUE := Color("#40318d")
const YELLOW := Color("#bfce72")
const ORANGE := Color("#8b5429")
const BROWN := Color("#574200")
const LIGHT_RED := Color("#b86962")
const DARK_GREY := Color("#505050")
const GREY := Color("#787878")
const LIGHT_GREEN := Color("#94e089")
const LIGHT_BLUE := Color("#7869c4")
const LIGHT_GREY := Color("#9f9f9f")

const GRASS := GREEN
const GRASS_DARK := Color("#4a9140")
const ASPHALT := DARK_GREY
const KERB_RED := Color("#c0392b")

## One body colour per car slot (0,1 = humans, 2..5 = CPU).
const CAR_COLORS := [
	Color("#e04a3a"), Color("#67b6bd"), Color("#e8e070"),
	Color("#b05ad0"), Color("#f2f2f2"), Color("#ef9a3a"),
]

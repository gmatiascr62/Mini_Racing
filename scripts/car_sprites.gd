class_name CarSprites
extends RefCounted
## Builds pre-rotated pixel-art F1 car sprites (like the rotation frames
## used by 8-bit racers) so cars stay crisp at any heading.

const FRAMES := 32
const SIZE := 16
## Facing right. B body, W wing, K tyre, H helmet.
const MAP := [
	"KKK...KK....",
	"KKK...KK..W.",
	"WBBBBBBBBBW.",
	"WBBBHBBBBBBB",
	"WBBBBBBBBBW.",
	"KKK...KK..W.",
	"KKK...KK....",
]

static var _cache: Dictionary = {}


static func frames_for(color: Color) -> Array:
	var key := color.to_html()
	if _cache.has(key):
		return _cache[key]
	var frames: Array = []
	var mh := MAP.size()
	var mw: int = MAP[0].length()
	var wing := color.darkened(0.45)
	var helmet := Color("#ffe14a") if color.get_luminance() < 0.75 else Color("#3050d0")
	for f in range(FRAMES):
		var ang := TAU * f / FRAMES
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var c := cos(-ang)
		var s := sin(-ang)
		for y in range(SIZE):
			for x in range(SIZE):
				var dx := x + 0.5 - SIZE / 2.0
				var dy := y + 0.5 - SIZE / 2.0
				var sx := dx * c - dy * s + mw / 2.0
				var sy := dx * s + dy * c + mh / 2.0
				var ix := int(floor(sx))
				var iy := int(floor(sy))
				if ix < 0 or iy < 0 or ix >= mw or iy >= mh:
					continue
				var ch: String = MAP[iy][ix]
				var col := Color(0, 0, 0, 0)
				match ch:
					"B":
						col = color
					"W":
						col = wing
					"K":
						col = Color("#141414")
					"H":
						col = helmet
				if col.a > 0.0:
					img.set_pixel(x, y, col)
		frames.append(ImageTexture.create_from_image(img))
	_cache[key] = frames
	return frames


static func frame_index(heading: float) -> int:
	return posmod(int(round(heading / TAU * FRAMES)), FRAMES)

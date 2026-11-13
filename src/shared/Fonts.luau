-- The game's two type faces: Zekton (a squared sci-fi face) for headings, labels, signs and big numbers, and
-- Roboto Mono for data, logs and running text. The HUD (client/Hud), the kit's live screens (ScreenFeeds) and
-- the map kit generator all use these. No requires, so a lone copy of this module loads anywhere.
local ZEKTON = "rbxasset://fonts/families/Zekton.json"
local ROBOTO_MONO = "rbxasset://fonts/families/RobotoMono.json"

return {
	display = Font.new(ZEKTON, Enum.FontWeight.Bold),
	body = Font.new(ZEKTON, Enum.FontWeight.Regular),
	mono = Font.new(ROBOTO_MONO, Enum.FontWeight.Medium),
}

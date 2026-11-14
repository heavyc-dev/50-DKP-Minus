-- Pack: Forever. Feats specific to WoW Forever. Zone and race names still need
-- checking in game. Data only.
local _, ns = ...

ns:RegisterPack("Forever", {
    { id = "premium_edition", name = "Premium Edition", fine = 50, race = "Skyborne", signal = "FEAT_EARNED",
      hint = "Skyborne: earn anything at all.", flavor = "Paid extra to be fined." },
    { id = "skydiving_lesson", name = "Skydiving Lesson", fine = 50, rating = "B", race = "Skyborne", signal = "DEATH", when = { cause = "FALL" },
      tiers = { { 1, "Skydiving Lesson", 50 }, { 10, "Ground School", 100 }, { 50, "Flightless", 250 } },
      hint = "Skyborne: discover the wings are decorative.", flavor = "Born of the sky. Returned to the ground." },
    { id = "go_agane", name = "Go Agane", fine = 500, rating = "B", ruleset = "HARDCORE", signal = "DEATH",
      flavor = "Go agane." },
    { id = "appeal_denied", name = "Appeal Denied", fine = 500, rating = "B", ruleset = "HARDCORE", signal = "DEATH",
      when = { within = { "LOGIN", 60 } },
      flavor = "Dead within a minute of logging in. No appeals." },
    { id = "ruleset_tourist", name = "Ruleset Tourist", fine = 100, rating = "B", signal = "FEAT_EARNED", value = "rulesets", count = 3,
      hint = "Be fined under three different sets of rules.", flavor = "Consistently bad across every ruleset." },
    { id = "legacy_window_shopper", name = "Legacy Window Shopper", fine = 5, rating = "C", signal = "UI_OPEN", count = 100, when = { ui = "LEGACY" },
      hint = "Keep looking at the Legacy panel.", flavor = "It's the same as last time." },
    { id = "riverglades_welcome", name = "Riverglades Welcome", fine = 50, signal = "DEATH", when = { zone = "RIVERGLADES" },
      hint = "Die somewhere new.", flavor = "New zone. Same result." },
    { id = "castaway", name = "Castaway", fine = 50, signal = "DEATH", when = { zone = "ZEPHRAS" },
      hint = "Die on an island.", flavor = "Nobody is coming to get you." },
    { id = "classic_plus", name = "Classic Plus", fine = 50, signal = "FEAT_EARNED", when = { classicPlus = true },
      hint = "Something old and something new, same day.", flavor = "Old shame and new shame, together at last." },
})

# 50 DKP Minus

**Not a real DKP addon.** A joke-achievement addon for WoW Forever that fines you for dying in elevators.

Everyone starts at zero and goes down. Every feat is a fine, there is no way to earn DKP back, and the lowest balance in the guild is the "winner". It is not a loot system and it does not track anything useful.

```
[50 DKP Minus] Brakk: Mind the Gap (-50 DKP)
[50 DKP Minus] THAT'S A 500 DKP MINUS. Brakk: Vendored an Epic
```

## What it does

- **329 feats** across ten packs: Core, Nostalgia, Deaths, Habits, Social, Class, Professions, Forever, Seasonal and Crossover. Unearned feats show `???` and a cryptic hint. The worst ones show nothing until you earn them.
- **Five tiers of fine**: Petty (-5), Standard (-50), Severe (-100), Whelps (-250) and /gkick Worthy (-500).
- **Herald**: one line in guild or party chat when you are fined. At most one line a minute per channel; bursts collapse into a summary. Petty fines stay private. Nothing is ever sent to say, yell or public channels automatically.
- **Ledger** (`/minus`): statement, offences, guild leaderboard and settings, on parchment, in red ink.
- **Guild sync**: other users' balances appear on the leaderboard and on their tooltip.
- **For people without the addon**: whisper a user `!dkp` for their balance, or `!shame` for their rarest feat.

## Commands

| Command | Action |
| --- | --- |
| `/minus` or `/dkp50` | Toggle the ledger |
| `/minus share` | Preview a one-line summary and pick a channel |
| `/minus last` | Re-announce your latest fine |
| `/minus quiet` | Toggle quiet mode (announce nothing, answer no whispers) |
| `/minus hint` | A random hint for a feat you have not earned |
| `/minus changelog` | Print the changelog |

## What it reads

The addon never reads combat data. It does not use the combat log, damage or healing numbers, or anything Forever marks as a Secret Value. Feats are detected from ordinary signals: where and when you died, the death recap, your own chat messages, emotes, error messages, windows you open, vendors, mail, quests, group and guild events, and the clock.

Inside instances Forever blocks addon chat and hides incoming chat, so the addon sends nothing there. Announcements queue and go out after you leave.

## Status

This is a first release and it has **not yet been tested in game**. It is tested outside the game against a stubbed API (`tests/`), which checks that the files load, the catalog is consistent and the main signal paths award the right feats.

Every feat carries a detection rating:

| Rating | Count | Meaning |
| --- | --- | --- |
| A | 215 | Plain event or hook. Expected to work. |
| B | 104 | Heuristic (death recap, position, timing, name matching). Works in principle, needs tuning. |
| C | 10 | Unverified on Forever. Off unless you enable "Unverified feats" in settings. |

Known limits:

- Zone-based feats match by map ID or English zone name, and spell- and NPC-based feats match English names. On other locales those feats stay unearned; nothing breaks.
- Death causes come from the death recap when the client exposes it, with a fallback based on what you were doing (falling, drowning, fatigue).
- Elevator and other coordinate boxes in `Zones.lua` are rough.
- 56 feats from the original design are not included yet because they have no reliable signal.

## Adding a feat

Feats are rows in `Feats/*.lua`. No engine changes are needed unless the feat needs a new signal.

```lua
{ id = "mind_the_gap", name = "Mind the Gap", fine = 50, rating = "B", signal = "DEATH",
  when = { cause = "FALL", inBox = { "UC_ELEVATORS", "TB_LIFTS" } },
  tiers = { { 1, "Mind the Gap", 50 }, { 5, "Elevator Boss", 100 }, { 25, "Frequent Faller", 250 } },
  hint = "Some lifts are faster than others.", flavor = "The elevator boss claims another." },
```

The header of `Engine.lua` lists the available fields, and each file in `Signals/` lists the signals it fires. To suggest a feat, open an issue with the "Suggest a feat" template.

## Development

```
cd tests
npm ci
node run.js
```

Tagging a commit `vX.Y.Z` builds a release with the [BigWigs packager](https://github.com/BigWigsMods/packager).

## Credits

The name comes from a well-known piece of WoW community folklore. This addon ships no audio, art or text from that recording or from any other game.

MIT licensed. World of Warcraft is a trademark of Blizzard Entertainment; this project is not affiliated with or endorsed by Blizzard.

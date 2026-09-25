# Sky Bother to-do

## Rig-aware night score (replaces the Moon note in "Main limitation")

**Problem (2026-09-25):** on a bright-Moon night the night scores Marginal (59) while the
Flaming Star Nebula scores Excellent (89). Both are right by their own rules — the night's
Moon factor assumes any target (galaxies included), while a target's score accounts for its
distance from the Moon and the rig's dual-band filter — but to a beginner they contradict.

**Stopgap in place:** `nightLimitationPhrase` (Planner/ScoreNarrative.swift) adds
"…, though <best target> still scores <n>" when the Moon is the main limitation and the best
target is Excellent or better.

**The fix:** make the night's Moon factor reflect the rig. In `nightFactors`
(Planner/Planner.swift), when the rig has a dual-band filter and good emission targets
(`TargetType.respondsToNarrowband`) are up during the best stretch, ease the Moon penalty
toward what those targets actually experience — e.g. base it on the effective moonlight of the
night's top few targets rather than the raw Moon brightness. A night that's genuinely ruined
(no filter, or only broadband targets up) stays low.

**Before shipping:** compare night scores for moonlit and moonless nights, with and without a
filter, at a couple of sites (Bortle 7 yard, a dark site), and check the verdicts read
sensibly. Update Help's "Night Score" text. Then remove the stopgap note from
`nightLimitationPhrase`.

**Cost estimate:** modest code change (~20 lines) plus a careful comparison pass; do it with a
fresh week's budget. It also carries into the web version's shared engine.

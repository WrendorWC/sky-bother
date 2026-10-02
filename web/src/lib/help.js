// Help for the web app: the Mac's HelpView.swift topics, reworded for a
// browser (no menus or keyboard shortcuts, tap as well as click, settings
// that wait for Save, sync joined per browser). Keep the two in step when
// either changes.
import * as palette from './palette.js';

const verdict = name => palette.verdictColor(name);

export const topics = [
  {
    id: 'start', title: 'Getting Started', sections: [
      { body: 'The Setup Wizard runs the first time you open Sky Bother in a browser: your site, horizon, telescope and goal. Only the site is required; the other steps have sensible defaults. Its first step also lets you bring everything across from the Mac app — with a sync code, or a settings file.' },
      { heading: 'Running It Later', body: 'Settings → Location → Setup Wizard.' },
      { heading: 'On Your Phone', body: 'Everything works on a phone. Tap where you’d click. Session View is made for using at the telescope.' },
    ],
  },
  {
    id: 'scores', title: 'Scores & Verdicts', sections: [
      { body: 'Every night and every target gets a score from 0 to 100. It’s a weighted geometric mean of several factors, so one very poor factor — no clear sky, or no time above the horizon — pulls the score down hard.' },
      {
        heading: 'Verdicts', body: 'Scores fall into five verdicts, shown as a coloured tag:', swatches: [
          [verdict('Exceptional'), '90 and above — Exceptional'],
          [verdict('Excellent'), '75–89 — Excellent'],
          [verdict('Good'), '60–74 — Good'],
          [verdict('Marginal'), '45–59 — Marginal'],
          [verdict('Poor'), 'Below 45 — Poor'],
        ],
      },
      { heading: 'Night Score', body: 'Clear dark time (35%), sky clarity (30%), the Moon (25%) and conditions such as wind and dew (10%). Clear dark time and clarity come from the night’s best imaging window — its best unbroken stretch of dark sky — measured against your integration goal. Cloud over your limit counts against the night gradually rather than all at once; see Cloud: No Hard Cutoff below. A night never scores higher than the best target you can shoot on it. Tap “Why this score” on a night to see each factor.' },
      { heading: 'Cloud: No Hard Cutoff', body: 'Your maximum cloud cover is where cloud starts to cost, not a wall. An hour at or under it counts in full. Over it, every 6 points halves what the hour counts for: with a 20% limit, 26% counts half, 32% a quarter and 38% an eighth, and by about 46% it counts for nothing. Clear dark time, the best imaging window and every target’s usable time are all counted this way.\n\nWhy: with a hard cutoff, a night hazy at 22–28% all night scored 21, the same as an overcast night, while another with the same average cloud that cleared for four hours scored 80. A band that stopped counting 10 points over the limit only moved that edge. Halving has no edge anywhere, so scores fall steadily as cloud rises. On a real week with a 20% limit, nights at 30%, 38%, 42% and 50% cloud scored 78, 51, 43 and 24. Six points is a judgment call: 5 left a 30-point gap between the 30% and 38% nights, and 7 lifted nights near 50% cloud into the high 30s.' },
      { heading: 'Target Score', body: 'Time on target (24%), detectability (20%), sky darkness (17%), cloud cover (17%), framing (14%) and altitude (8%). Night and target scores are independent: a good night can still be a poor one for a particular target.' },
      { heading: 'Same as the Mac', body: 'The web app runs the Mac app’s own scoring, so the same site, rig and settings give the same scores — as long as both have the same forecast. If the main forecast service is unreachable the web uses a backup and says so under the night list; scores can differ until it’s back.' },
    ],
  },
  {
    id: 'timeline', title: 'The Night Timeline', sections: [
      {
        heading: 'Layers', body: '', swatches: [
          [palette.css(palette.astronomical), 'Background — sky darkness, from daylight through twilight to full dark, with stars once it’s properly dark. The stars dim as cloud thickens, and the sky dulls where cloud is past your cloud limit'],
          [palette.css(palette.cloud), 'Grey from the top — forecast cloud; the deeper it reaches, the cloudier'],
          [palette.css(palette.moonlight), 'Pale wash and line near the bottom — moonlight and the Moon’s altitude'],
        ],
      },
      { heading: 'Lines', body: 'The dotted lines mark astronomical dusk and dawn. The red line marks the current time on tonight’s chart.' },
      { heading: 'Pointing or Touching', body: 'Point at the chart (or touch it) for the time, cloud with its high, mid and low layers, temperature, darkness and the Moon’s altitude. With a target selected, its altitude too.' },
      { heading: 'Selected Target', body: 'A selected target’s altitude curve and best window are drawn over the chart.' },
    ],
  },
  {
    id: 'sky', title: 'Sky View', sections: [
      { body: 'The sky as a dome: the zenith in the centre, the horizon at the rim, north at the top. The small sky picture in a night’s summary opens it, showing tonight’s sky as it is now (any other night’s in the middle of its best imaging window). Sky View shows the plan but never changes it.' },
      { heading: 'What’s Drawn', body: 'The real sky at the chosen time, with twilight and moonlight brightening it as they would outside, and cloud drifting across it in proportion to the forecast (not where the clouds really are). The plan’s targets and famous ones are marked; tap one for its card. The brightest stars are named, faintly, to find your way around by.' },
      { heading: 'Target Path', body: 'The selected target’s full daily path around the pole: solid purple above the horizon, faint below it, amber where it passes through zenith risk.' },
      { heading: 'Zenith Risk', body: 'Alt-az mounts, including every smart telescope, rotate the field fastest overhead and some stall near the zenith. Time a target spends above the rig’s zenith limit (Settings → Equipment → Warn above, default 80°) is drawn amber on its path. It doesn’t apply to equatorial mounts, and can be turned off in Settings → Equipment.' },
      { heading: 'Your Frame', body: 'Your camera’s frame is drawn to scale on the selected target. On a wide screen, “Camera roll” rotates it. It isn’t drawn below the horizon or within 2° of the zenith. On an alt-az mount it turns through the night — that’s real field rotation.' },
      { heading: 'Playback', body: '“Play the Night” runs the night in about 25 seconds; dragging the time bar pauses it. “Now” shows the sky as it is now and keeps up with the clock — a red dot shows it’s live. “Follow planned targets” selects each planned target while its block runs, fading from one to the next; “Stay on selected target” keeps the selection. Tap a block on the plan strip to jump to it.' },
    ],
  },
  {
    id: 'plan', title: 'The Plan', sections: [
      { body: 'A night’s page shows its plan: the app’s suggestion — the best non-overlapping targets above your minimum score — or your own. Change it in the planner. Below the plan are the best unplanned targets (“If it clears” on a clouded-out night).' },
      { heading: 'Suggested or Yours', body: 'A suggested plan updates with the forecast and your settings. It becomes yours when you change it and press Done, and then stays as you left it. “Reset to Suggested” in the planner goes back to the suggestion. Plans sync with your other devices if sync is on.' },
      { heading: 'The Planner', body: '“Plan Session” or “Edit Plan” opens it: the session timeline at the top, candidates below, and on a wide screen the selected block or target beside them. Nothing is saved until Done; Cancel throws your changes away.' },
      { heading: 'Editing', body: 'Drag a block to move it, or an edge to resize it; times snap to five minutes. With a block selected, ← → move it five minutes, Shift-arrows change its end, Option- or Alt-arrows its start, and Delete removes it.' },
      { heading: 'Reordering', body: 'Drag a block into its neighbour and the neighbour shortens. Keep going and it swaps to the other side. Dragging an edge shortens neighbours but never swaps them. Blocks never overlap.' },
      { heading: 'Adding Targets', body: 'Add puts a block in the longest free stretch, preferring time the target can actually be shot. The same target can have several blocks. Filter candidates by name, “Fits my frame” and usable time.' },
      { heading: 'Longer Integration or More Targets', body: 'Sets how the suggestion shares a short night. Longer integration gives each target up to your full integration goal and nothing under a third of it. More targets halves that, down to 20 minutes. It doesn’t change a plan you’ve made yourself.' },
      { heading: 'Unshootable Time', body: 'Blocks can cover time when the target isn’t up, dark or clear. That part is hatched and its minutes are totalled. Clouded-out nights get no suggestion.' },
    ],
  },
  {
    id: 'session', title: 'Session View', sections: [
      { body: '“View Session”, on tonight’s page when it has a plan, opens Session View, the plan for use at the telescope: what’s on now and how long is left, or what’s next and when it starts; your frame on the target and the sky as it is right now; then the conditions at this minute — temperature and dew point, cloud by layer, wind, how dark the sky is, the Moon and how long darkness lasts — a few facts about the target, and what comes after. When dew risk is High or worse, it says when to turn on your dew heater. It follows the clock, so there’s nothing to press. On a phone, “Keep Screen On” stops it going to sleep (where the browser allows).' },
      { heading: 'Night Mode', body: 'The moon button in the toolbar (or Settings → Display) turns the whole page red, pictures and charts included, so looking at the screen doesn’t cost you your dark adaptation. Turn the screen brightness down as well. It stays on this device; sync leaves it alone.' },
      { heading: 'A Seestar’s Live Picture', body: 'The Mac app can show the stack a Seestar is building. A browser can’t reach a telescope on your network, so the web app can’t.' },
    ],
  },
  {
    id: 'bars', title: 'Availability Bars', sections: [
      { body: 'Each target has a bar on the same time axis as the timeline. It fills when the target is above your minimum altitude, the sky is dark enough and cloud is under your maximum. Gaps are usually cloud. The line through it is the target’s altitude; the tick marks its best moment. On a plan block’s row the bar shows the target’s whole night, with the block itself lit up and the rest dimmed.' },
      { heading: 'Figures', body: 'Under each bar: best time, peak altitude and how much of the frame it fills.' },
    ],
  },
  {
    id: 'frame', title: 'In Your Frame', sections: [
      { body: 'A Digitized Sky Survey image centred on the target at your rig’s field of view, with your frame drawn on it. Green means it fits; dashed amber means it needs a mosaic. The cross marks the catalogued position — faint targets can be hard to see in the survey.' },
      { heading: 'Rig Presets', body: 'Presets use published specifications. Check them against your own equipment; every number can be edited in Settings → Equipment → Optics.' },
    ],
  },
  {
    id: 'weather', title: 'Cloud, Moon & Weather', sections: [
      { heading: 'Cloud', body: 'Cloud figures are weighted by layer: low cloud counts fully, mid-level 85%, high cirrus 50%. Your maximum cloud cover is checked against this figure.' },
      { heading: 'Moon', body: 'The Moon doesn’t shorten the night; it lowers each target’s score depending on phase and the Moon’s altitude. A bright Moon lights the whole sky, so pointing away from it helps only a little; within about 30° of it the penalty is much worse. A dual-band filter softens the penalty somewhat for emission and planetary nebulae and supernova remnants. Tap the Moon on a night’s page to see it as it will look that night.' },
      { heading: 'Seeing', body: 'Estimated from wind gusts only. Treat it as a hint.' },
      {
        heading: 'Dew Risk', body: 'From the gap between temperature and dew point: over 10°F Low, 6–10°F Moderate, 3–6°F High, 3°F or less Very High. Clear, calm nights raise it one step, because optics cool below the air. At High and above, Session View says when to turn the dew heater on.', swatches: [
          [palette.dewColor('Low'), 'Low — dew heater probably unnecessary'],
          [palette.dewColor('Moderate'), 'Moderate — watch your optics'],
          [palette.dewColor('High'), 'High — dew heater recommended'],
          [palette.dewColor('Very High'), 'Very High — dew heater recommended'],
        ],
      },
    ],
  },
  {
    id: 'site', title: 'Your Site', sections: [
      { heading: 'Bortle Class', body: '1 (pristine) to 9 (city centre). It sets the sky brightness used for detectability, so it matters a lot. A light-pollution map will tell you yours.' },
      { heading: 'Blocked Horizon', body: 'How high trees, buildings and hills reach, in Settings → Location. “Everywhere” sets one value all the way round; the eight sliders below it set each direction. Targets are skipped only while they’re behind the direction they’re in.' },
      { heading: 'More Than One Spot', body: 'Picking a new place saves the one you’re leaving to your saved sites, so you can switch back with Use — a front yard and a back yard can each keep their own horizon.' },
    ],
  },
  {
    id: 'settings', title: 'Settings', sections: [
      { heading: 'Save', body: 'Changes in Settings wait for Save — nothing changes, here or on your synced devices, until you tap it. Cancel throws them away. Settings that stay on this device (Display) are marked as such.' },
      { heading: 'Goal', body: 'Quick session, Deep integration and Variety each set the integration goal and plan emphasis; “Fine-tune” changes them, which makes it Custom.' },
      { heading: 'Maximum Cloud Cover', body: 'Cloud up to this counts as clear. Over it, every 6 points halves what an hour counts for. See Scores & Verdicts → Cloud: No Hard Cutoff for why. Around 20% works well.' },
      { heading: 'Minimum Darkness', body: 'How far below the horizon the Sun must be for the sky to count as dark. 18° is full astronomical darkness.' },
      { heading: 'Minimum Altitude', body: 'Targets lower than this are skipped, even where the horizon is open.' },
      { heading: 'Hide Targets Scoring Below', body: 'Targets under this score are left out of lists and suggestions. It doesn’t change any score.' },
      { heading: 'Nights Ahead', body: 'How many nights to plan. Cloud forecasts beyond about a week are unreliable.' },
    ],
  },
  {
    id: 'sync', title: 'Sync & Sharing', sections: [
      { body: 'Sync keeps your sites, telescope, settings and plans the same here, on your phone and in the Mac app. There’s no account: one device turns sync on and gets a code, and every other one enters it (Settings → Sync). Everything is encrypted on the device before it leaves, so the server only ever holds a copy it can’t read. Each device keeps its own UI scale, night mode and units.' },
      { heading: 'Each Browser Joins Once', body: 'A browser keeps its settings and sync code to itself, so each browser on each device joins on its own — turning sync on in your phone’s browser doesn’t turn it on in the one on your computer. The Sync tab’s dot is green while this browser is syncing and grey while it isn’t; a browser that isn’t syncing keeps its own copy.' },
      { heading: 'Joining', body: 'Joining takes the synced copy as it is, replacing this browser’s. To bring a browser that has drifted back into line, turn sync off on it and join again.' },
      { heading: 'Setup Link', body: 'A one-time link that gives another device, or a friend, your site, telescope and settings. Unlike sync, it doesn’t keep them in step afterwards.' },
      { heading: 'From the Mac App', body: 'File → Export Settings… in the Mac app saves a settings file; Settings → Sync → Import Mac Settings File here reads it, saved sites, rigs and plans included.' },
    ],
  },
  {
    id: 'catalog', title: 'The Catalog', sections: [
      { body: '“Catalog” in the toolbar. Every target is scored for one night, chosen at the top. Cards show the score, verdict, usable time and framing.' },
      { heading: 'Sorting and Filters', body: 'Sort alphabetically, by best on the night, longest window, size or brightness; filter by type, to Good or better, Fits my frame, or a minimum usable time.' },
      { heading: 'Stars', body: 'The brightest named stars, plus doubles and red stars that suit a small scope, such as Albireo, Mizar and Alcor, and the Garnet Star. They’re scored on their own terms: they shine through moonlight and need only minutes. A double is judged on whether your rig splits it. Stars are never the night’s best target or part of a suggested plan; add them yourself. To hide them, switch off “Bright stars and doubles” in Settings → Planning.' },
      { heading: 'Custom Targets', body: '“+ Add Custom Target” at the top of the catalog adds anything it’s missing: a designation, type, position (as star charts give it — 21h 11m 48s and +59° 59′ — or in decimal degrees), magnitude and size. Custom targets are scored and planned like any other, sync with your other devices and the Mac app, and are marked Custom; Edit changes or deletes one.' },
      { heading: 'Comets', body: 'Every comet predicted brighter than magnitude 14 on a night is a target that night, placed where it is then. Comets are scored like deep-sky objects, with the coma’s size guessed from its brightness. Brightness predictions for comets are often a magnitude or more out, either way, so treat the score as a guide. To hide them, switch off “Visible comets” in Settings → Planning.' },
    ],
  },
  {
    id: 'data', title: 'Data Sources', sections: [
      { heading: 'Weather', body: 'Open-Meteo, free and keyless. In the US and southern Canada the cloud totals come from NOAA’s National Blend of Models. If Open-Meteo is slow or unreachable, MET Norway is used and the night list says “backup source”.' },
      { heading: 'Astronomy', body: 'Sun, Moon and target positions and all rise, set and twilight times are computed in your browser, by the same code as the Mac app. The Sun is accurate to about 0.01°, the Moon to a few arcminutes.' },
      { heading: 'Catalog', body: 'About 1,150 targets: the Messier catalogue, 49 other showpieces and about 1,000 NGC/IC objects from OpenNGC (CC-BY-SA-4.0), plus 58 bright and double stars from SIMBAD. Positions are J2000.' },
      { heading: 'Comets', body: 'Orbits from the IAU Minor Planet Center.' },
      { heading: 'Images', body: 'Framing images: Digitized Sky Survey (STScI/NASA), colour by CDS. Photographs: Wikipedia, credited under each. Sky View star map: NASA Goddard SVS Deep Star Maps 2020, from Gaia DR2, Hipparcos-2 and Tycho-2. Moon: NASA SVS CGI Moon Kit, from Lunar Reconnaissance Orbiter data.' },
      { heading: 'Places', body: 'Place search: Open-Meteo’s geocoder and, for postal codes, OpenStreetMap Nominatim.' },
    ],
  },
];

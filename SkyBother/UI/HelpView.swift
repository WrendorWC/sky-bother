import SwiftUI

/// A colour-key row, so a help section can point at the exact hue used
/// on-screen rather than just naming it.
struct HelpSwatch: Identifiable {
    var id: String { label }
    var color: Color
    var label: String
}

/// One block of explanatory text, with an optional heading and an optional
/// row of colour swatches for anything that leans on colour to communicate.
struct HelpSection: Identifiable {
    var id: String { heading ?? body }
    var heading: String?
    var body: String
    var swatches: [HelpSwatch] = []
}

struct HelpTopic: Identifiable {
    var id: String { title }
    var title: String
    var systemImage: String
    var sections: [HelpSection]
}

enum HelpContent {
    static let topics: [HelpTopic] = [
        HelpTopic(title: "Scores & Verdicts", systemImage: "target", sections: [
            HelpSection(body: "Every night and every target gets a score from 0 to 100, shown in the coloured circle — a weighted geometric mean of several factors (each on a 0 to 1 scale), not a simple average. A geometric mean punishes a single near-zero factor — no clear sky, say, or no time above the horizon — hard, rather than letting good scores elsewhere paper over it."),
            HelpSection(heading: "The Coloured Tag", body: "Each score is grouped into one of five verdicts, shown as a coloured pill beside the date or target name. All five sit on one red-to-green scale, so colour means the same thing everywhere in the app: red is worse, green is better. Exceptional gets a brighter, more saturated green with a glow, reserved for a night or target that's well above an ordinary good result:", swatches: [
                HelpSwatch(color: Palette.exceptional, label: "90 and above — Exceptional"),
                HelpSwatch(color: Palette.go, label: "75–89 — Excellent"),
                HelpSwatch(color: Palette.good, label: "60–74 — Good"),
                HelpSwatch(color: Palette.marginal, label: "45–59 — Marginal"),
                HelpSwatch(color: Palette.skip, label: "Below 45 — Poor")
            ]),
            HelpSection(heading: "Night Score vs. Target Score", body: "A night's score weighs clear dark time (35%), sky clarity (30%), the moon (25%), and conditions like wind and dew (10%). A target's score weighs time on target (26%), sky darkness (18%), cloud cover (18%), how well it fills the frame (15%), how detectable it is against the sky background (14%), and altitude (9%). The two are calculated independently, on purpose — a night can be excellent overall while one particular target is a poor match for it, or the other way around.")
        ]),

        HelpTopic(title: "The Night Timeline", systemImage: "chart.bar.xaxis", sections: [
            HelpSection(body: "This chart is what the rest of the app is built around. Every target's availability bar beneath it shares the same time axis, so reading straight down any column tells you exactly what's visible at that moment."),
            HelpSection(heading: "What the Layers Mean", body: "", swatches: [
                HelpSwatch(color: Palette.astronomical, label: "Background — actual sky darkness, progressing from daylight blue through civil, nautical and astronomical twilight to black"),
                HelpSwatch(color: Palette.cloud, label: "Grey layer descending from the top — forecast cloud cover; the further it extends downward, the cloudier that hour is expected to be"),
                HelpSwatch(color: Palette.moonlight, label: "Pale wash over the background, together with the traced line near the bottom — moonlight and the moon's altitude throughout the night")
            ]),
            HelpSection(heading: "The Dotted Lines and the Red Line", body: "The two dotted vertical lines mark astronomical dusk and dawn — the boundary this app treats as genuine darkness. The thin red line marks the current time, when you're looking at tonight's plan."),
            HelpSection(heading: "Hovering", body: "Hold the pointer over any point on the chart for an exact readout: time, cloud percentage, temperature, how dark it is (as a percentage), and the moon\u{2019}s altitude, if it\u{2019}s above the horizon. With a target selected, its own altitude at that moment is shown too, in the accent colour \u{2014} and if it\u{2019}s up but still behind your blocked horizon in the direction it\u{2019}s currently in, the readout says so and names the direction, which is the difference between waiting an hour and giving up on it."),
            HelpSection(heading: "When a Target Is Selected", body: "Selecting a target from the list overlays its altitude curve, usable windows and single best window onto the sky and cloud layers, all in the app's one accent colour so a selection reads the same here as everywhere else. You can read the best window, and the reasoning behind it, off one chart without switching views.")
        ]),

        HelpTopic(title: "Sky View", systemImage: "globe", sections: [
            HelpSection(body: "Sky View is a classic planisphere: the zenith sits at the centre, the horizon forms the outer rim, and azimuth runs around the edge like a compass face — the N/E/S/W labels mark it. It's collapsed by default beneath the main timeline (look for the disclosure triangle) and shares that timeline's own scrubbed time, so dragging the slider at the bottom moves both views together."),
            HelpSection(heading: "What's Drawn on It", body: "Only targets that clear your minimum score, type and search filters — the same ones the target list already applies — show up as dots here, so this stays a map of what's actually worth pointing at rather than every catalogued object above the horizon. (The one exception: your selected target always shows, even if it wouldn't otherwise clear the filter, since you're looking right at it.) Each unselected dot is coloured by its own score — the same red-to-green ladder shown under \"Scores & Verdicts\" — with real transparency, not just a muted fill, so a genuinely crowded patch of sky (usually along the Milky Way) reads as visibly denser instead of one dot silently hiding behind another; where two do overlap, the better-scoring one always draws on top. Size follows real catalogued extent on a logarithmic scale, since real sizes span everything from under an arcminute to several degrees — a straight linear scale left almost everything the same tiny dot, where log scaling keeps a 2′ galaxy visibly smaller than an 8′ one while still stopping a genuinely huge target like M31 from swallowing its neighbours.", swatches: [
                HelpSwatch(color: Palette.moonlight, label: "The Moon — a plain disc, sized to its real apparent diameter for tonight's actual distance, only drawn while it's above the horizon"),
                HelpSwatch(color: Palette.accent, label: "The selected target — always drawn in the app's one purple selection colour rather than its score colour, with a halo ring, so \"selected\" never gets confused with \"good\""),
                HelpSwatch(color: Palette.cameraFrame, label: "Camera Frame overlay (toggle above the view) — a clean near-white viewfinder outline showing the configured rig's actual field of view"),
                HelpSwatch(color: Palette.milkyWay, label: "Milky Way band (toggle above the view) — the galactic plane's real width, drawn as two nested translucent ribbons rather than a single line"),
                HelpSwatch(color: Palette.accentWarm, label: "Galactic Core marker — a small warm-coloured dot on the Milky Way band, deliberately a different hue from both selection purple and the quality scale so it never reads as either")
            ]),
            HelpSection(heading: "The Selected Target's Path", body: "Once a target is selected, its full day-long track is traced as a closed loop around the sky — a real fixed-coordinate target genuinely circles the pole once a day, and drawing the whole loop instead of stopping it at dusk and dawn is what makes that shape read as a real orbit rather than an arc that just happens to begin and end at nightfall. The portion above the horizon draws as a solid purple line; the rest of the loop, while it's below the horizon and out of reach, continues on as a faint one instead of vanishing, so the ring stays visibly whole. Wherever the above-horizon portion passes through a zenith-risk span (see below), it switches to amber instead of purple, the same amber used for warnings throughout the app. The target's dot always sits on its own path, at whatever point corresponds to the current scrubbed time."),
            HelpSection(heading: "Zenith Risk, in Amber", body: "Alt-azimuth mounts — every current smart telescope — rotate the field fastest directly overhead, and some stall mechanically near the zenith altogether. \"Zenith Risk\" marks the real span of time a target spends above the zenith-avoidance altitude configured for the active rig in Settings → Equipment (default 80°, set to 90° to disable). It's the same underlying data behind the amber path here, the segmented time bar and warning triangle on a target's own detail page, and the warning triangle on ranked target rows and Tonight's Plan — one real time window, shown wherever a time window already appears, rather than a fact that only exists buried in a warning sentence. It's already irrelevant on an equatorial mount — none of this is ever computed for one — and \"Show zenith risk warnings\" in Settings → Equipment turns it off on an alt-az rig too, if it's just noise to you."),
            HelpSection(heading: "Camera Frame & Milky Way Toggles", body: "Both are per-viewing toggles, not saved settings. Turning on Camera Frame reveals a rig picker (any preset or saved rig, previewed here without changing the active one used for scoring) and a roll slider, since the frame's on-sky orientation at imaging time isn't something the app can know on its own. The frame is only drawn when it clears the horizon entirely — a frame dipping below the rim isn't clipped, it's simply not shown, with the readout beneath the view explaining why. On an alt-az rig, the frame visibly rotates as you scrub through the night — that's real field rotation, the same effect behind Zenith Risk, not an animation. On an equatorial rig it holds one orientation relative to the stars all night instead, same as the real mount does."),
            HelpSection(heading: "The Readouts Beneath the Scrubber", body: "As you drag the time slider, the line beneath it reports the selected target's live altitude and compass direction, the Galactic Core's position and whether it's above 20° (with Milky Way on), and — with Camera Frame also on — whether the Core roughly fits inside the current frame."),
            HelpSection(heading: "Playing Through the Night", body: "The round button beside the slider plays the whole chart window forward on its own, about 25 real seconds per evening, rather than dragging by hand. If Tonight's Plan has anything in it, two chips appear on the readout line to choose what playback does with the selection: \"Track Selected\" holds whatever's currently selected fixed while time advances, and \"Cycle Plan\" hands the selection off from one planned target to the next as playback crosses into each one's own scheduled window, so the detail pane on the right walks through the whole session with it. Which one is picked resets every time the selection itself changes: choosing something from tonight's plan — or nothing at all — defaults to Cycle Plan, while choosing anything else (browsing the full catalogue, say) switches to Track Selected automatically, since there'd be nothing of the plan left to hand off to otherwise. Either chip can still be tapped directly to override that default until the next selection change. Dragging the slider or tapping a dot by hand always pauses playback rather than fighting it.")
        ]),

        HelpTopic(title: "Tonight's Plan", systemImage: "list.number", sections: [
            HelpSection(body: "This section, above the target list, is the app's own suggested session: the highest-scoring non-overlapping targets that clear your minimum score, each given a contiguous block of time."),
            HelpSection(heading: "One Target vs. Several", body: "When only one target clears the bar, it's shown as a single compact line — name, time window, duration — rather than the same target repeated as a timeline block, a plan row, and a ranked result underneath. The graphical Gantt-style strip only appears once there are two or more targets, since that's when relative order and overlap actually carry information worth a chart."),
            HelpSection(heading: "Zenith Risk Here Too", body: "A target whose planned window overlaps a zenith-risk span (see \"Sky View\") gets the same small amber warning triangle shown on ranked target rows, with a tooltip giving the time it starts."),
            HelpSection(heading: "Manual or Suggested", body: "The badge beside the section title says whose plan you are looking at. \u{201c}Suggested\u{201d} is the app\u{2019}s own, rebuilt whenever the forecast or your settings change. \u{201c}Manual\u{201d} means you have edited that night: it then stays exactly as you left it and nothing re-plans it, which is also what makes \u{201c}Reset\u{201d} meaningful \u{2014} that button throws away real work on a manual plan and does nothing at all to a suggested one. Plans are saved per night and survive quitting; nights that have already passed are dropped on the next launch, since this is a planner rather than a logbook."),
            HelpSection(heading: "Editing the Plan", body: "\u{201c}Edit plan,\u{201d} beside the section title, turns the strip into something you build on \u{2014} it takes on the accent-coloured border while it\u{2019}s live. It starts from whatever the app was already suggesting, since the scheduler usually has the shape of the night about right and the edits worth making are moving one block and splitting another. Drag a block along the night to move it; drag either end to change how long you spend there. Every edit snaps to the nearest five minutes so times stay readable. \u{201c}Clear\u{201d} empties the night and leaves it empty; \u{201c}Reset\u{201d} throws your version away and hands the night back to the scheduler. \u{201c}Done\u{201d} puts the strip back to being a picture \u{2014} your plan is saved either way, per night, and survives quitting the app."),
            HelpSection(heading: "Pushing Blocks Around", body: "Drag a block into its neighbour and the neighbour shortens from the side being encroached on, the way dropping a clip onto a video timeline does. Keep pushing and it would eventually vanish, which is never what was meant \u{2014} so at the point it would drop below ten minutes it hops to the other side of the block you\u{2019}re dragging, at its full original length. That is how you reorder: push a block far enough into its neighbour and the two change places. Push far enough and a third block will get out of the way too, moving to the nearest gap that fits it. Dragging an *end* trims the same way but never makes anything swap \u{2014} that\u{2019}s a statement about how long you spend on this target, and a neighbour leaping across the night in response would be absurd. Blocks never overlap, because one telescope points at one thing at a time; when no arrangement works the block simply stops."),
            HelpSection(heading: "The Same Target More Than Once", body: "While editing, every row in the target list below gets a + button that drops a block for it into the longest gap left in the night, preferring time the target can actually be shot in. Pressing it twice gives you two blocks of that target, which is the point: \u{201c}M31 for ninety minutes, NGC 1514 for two hours, then back to M31\u{201d} is a perfectly ordinary night, and a suggested plan can\u{2019}t express it because a suggestion holds each target at most once. The \u{2212} button on a plan row removes that one block, not the target."),
            HelpSection(heading: "Longer Integration or More Targets", body: "Settings \u{2192} Planning chooses which way the suggested plan leans when the night is shorter than the targets that want it. \u{201c}Longer integration\u{201d} hands no target more than your full Integration Goal before the others get a turn; \u{201c}More targets\u{201d} halves that, so roughly twice as many fit. Either way, time nobody else wants is still given back afterwards \u{2014} a night with one real target on it keeps the whole night. This only shapes what the app suggests: a plan you have edited by hand is yours, and changing this never rearranges it."),
            HelpSection(heading: "Clouded-Out Nights", body: "A night the forecast writes off entirely gets no plan at all \u{2014} there is nothing to schedule. The target list below still fills in, re-worked as though the cloud weren\u{2019}t there, so you can see what you\u{2019}d have had if it clears; a running order built from those would be a schedule for a night that isn\u{2019}t happening."),
            HelpSection(heading: "Hatched Blocks", body: "A block can be dragged anywhere, including to a time its target isn\u{2019}t up, isn\u{2019}t dark, or is forecast cloudy. That part of the block is drawn with diagonal hatching, the row underneath says how many minutes are affected, and the section header totals it across the whole plan. It\u{2019}s flagged rather than prevented on purpose \u{2014} a forecast is a forecast, and planning through a cloud band you don\u{2019}t believe in is your call to make. A block whose target has dropped out of tonight entirely is drawn in red and hatched end to end."),
        ]),

        HelpTopic(title: "Target Availability Bars", systemImage: "chart.xyaxis.line", sections: [
            HelpSection(body: "Each row in the target list has its own thin bar, sharing the night timeline's axis. Beneath it, a faint white line traces the target's altitude as it rises and sets — pure geometry, drawn even through hours when the target isn't usable."),
            HelpSection(heading: "What the Green Fill Means", body: "A segment fills, in the same colour as the target's score badge, only when all three hold at once: the target's above your minimum altitude, the sky's dark enough for your darkness threshold, and forecast cloud cover is under your maximum. A real three-way AND, checked every five minutes."),
            HelpSection(heading: "Why There Can Be Gaps", body: "Altitude rises then falls once a night, and once astronomical darkness starts it stays — neither one reverses partway through. Cloud cover isn't one-directional, though: if the forecast dips below the threshold, climbs back over it, then drops again, you'll see separate green segments with real gaps between them — not a rendering bug. The bright vertical tick marks that target's single best moment."),
            HelpSection(heading: "Example: Double Cluster", body: "If tonight's Double Cluster bar is one solid green block, it's above the horizon, the sky's dark, and the forecast stays clear the whole time. Two blocks with a gap between them mean the same thing, except a cloud patch is forecast in between — check the main timeline at that time and you'll see the grey cloud layer reaching further down."),
            HelpSection(heading: "The Line Beneath the Bar", body: "Beneath each availability bar sits one line of fixed-order figures — best time, peak altitude, percentage of the frame's long side filled, and total usable time — always in that order, so scanning straight down the list compares the same value in the same place on every row rather than parsing a differently-shaped sentence each time. A small amber warning triangle appears at the end of the line, with a tooltip on hover, whenever that target's best window passes through a zenith-risk span; see \"Sky View\" for what that means.")
        ]),

        HelpTopic(title: "\"In Your Frame\"", systemImage: "camera.viewfinder", sections: [
            HelpSection(body: "This panel, on each target's detail page, answers something a magnitude figure alone can't: will this actually produce a meaningful image through your specific telescope and sensor?"),
            HelpSection(heading: "Reading It", body: "The ellipse (or photo, where the catalogue has one) is the target's real catalogued size, drawn to scale against your rig's field of view — the rectangle. Solid green means it fits comfortably in a single frame. Dashed amber means it's oversized and would need a mosaic, or is being shown anyway because oversized targets are allowed in Settings. The number under the target is its apparent size in the sky; the number in the frame's corner is your configured field of view, in degrees."),
            HelpSection(heading: "The Photograph", body: "Where one exists, the photo comes from Wikipedia and is clipped to the same ellipse — a real view of the object, not just a schematic shape. The link beneath the panel credits the source. Not every target in the catalogue has one."),
            HelpSection(heading: "The Faint Stars and Grid", body: "The scattered points and faint alignment lines behind the ellipse and frame are decorative only — a fixed pattern generated from the target's own catalogue number, not a real star field, and not part of the size or fit calculation. They're deliberately dim so the ellipse and frame stay the two things your eye actually lands on.")
        ]),

        HelpTopic(title: "Score Breakdown", systemImage: "list.bullet.rectangle", sections: [
            HelpSection(body: "The \"Why This Score\" section on each target's page lists every factor in its geometric mean, each with its own rating (Exceptional to Poor) and a bar scaled 0 to 100 percent. A line beneath each bar gives the real number behind it — actual usable minutes, actual surface brightness, and so on."),
            HelpSection(heading: "The \"−N\" Value Beside Each Factor", body: "This number is calculated, not estimated: set that one factor to its perfect value (1.0), recompute the geometric mean, and subtract the actual score. That's exactly how many points that factor is costing right now — not a fixed share of its weight, since in a geometric mean what one factor costs depends on all the others too. \"Main Limitation\" at the top is just whichever factor has the biggest −N."),
            HelpSection(heading: "\"Why Not Recommended\"", body: "Targets rated Marginal or Poor get a short list of real reasons, pulled from whichever factors are actually weakest — not a generic explanation."),
            HelpSection(heading: "Detectability", body: "This measures surface brightness against the sky background, not just the raw catalogue magnitude. The target's light gets spread across its full catalogued size and compared to your Bortle-class sky background, adjusted for f-ratio, integration time and any filter in use — which is why the same galaxy can score well from a dark site and near zero from a city, on an otherwise identical clear night. It carries more weight than the other quality factors and is allowed to pull a score much further down, because it\u{2019}s the only one that can be fatal: an hour of cloud costs you part of a night, but a target fainter than the sky it sits on returns nothing at all, however long you leave the shutter open. When that\u{2019}s the case the target says so in its warnings, with the two brightness figures, rather than leaving you to infer it from a middling number."),
            HelpSection(heading: "Framing", body: "Full marks go to a target filling 30 to 80 percent of the frame's long side. Smaller under-uses the sensor; larger needs a mosaic, which costs a little if your rig supports mosaicking and a lot if it doesn't.")
        ]),

        HelpTopic(title: "Cloud, Moon & Weather Numbers", systemImage: "cloud.moon", sections: [
            HelpSection(heading: "Cloud Percentage", body: "Every cloud percentage you see — sidebar, night header, hover readout — is an effective figure, not the raw forecast. Open-Meteo splits cloud cover into low, mid and high layers; low cloud counts at full strength here, mid-level at 85 percent, and thin high cirrus at only 50 percent, since cirrus barely touches an image while low cloud wrecks it. Your \"Maximum Cloud Cover\" setting is checked against this effective figure, not the raw one."),
            HelpSection(heading: "Moon", body: "A bright moon doesn't shorten the night — darkness windows come from the sun alone — it's applied instead as a per-target quality penalty. That penalty scales with lunar phase raised to the power of 2.2 (a half moon is a lot less than half as bright as a full one), with the moon's own altitude, and with the target's angular separation from it. A dual-band filter cuts this penalty to 40 percent and adds contrast for emission nebulae, planetary nebulae and supernova remnants — which is why the app might recommend the Crescent Nebula under a gibbous moon while steering you away from a galaxy the same night."),
            HelpSection(heading: "Seeing & Dew", body: "Seeing is estimated from surface wind gusts. Real seeing depends on jet stream conditions, which no free forecast exposes — treat this as a hint, not a measurement. Dew risk gets flagged when the forecast dew-point spread (air temperature minus dew point) gets close to zero, since that's roughly where a corrector plate or lens starts to fog.")
        ]),

        HelpTopic(title: "Bortle Class & Your Site", systemImage: "mappin.and.ellipse", sections: [
            HelpSection(body: "Bortle class — 1 (pristine) to 9 (inner-city) — matters more than almost anything else in the app. You enter it by hand in Settings → Location, since no free API can actually measure your sky. It sets the zenith sky brightness behind every detectability calculation, which is why the same galaxy can be a non-starter from a Bortle 8 backyard and an easy target from a Bortle 4 site twenty miles away."),
            HelpSection(heading: "Blocked Horizon", body: "The altitude below which trees, buildings or terrain block your actual view. Anything that never climbs above it is treated as unobservable, no matter what the raw ephemeris says. The slider in Settings sets every direction at once, which is the right answer for most sites; open \u{201c}One direction is worse\u{201d} underneath it if something in particular \u{2014} one big tree, a neighbour\u{2019}s roof \u{2014} takes out part of your sky and the rest of it is fine."),
            HelpSection(heading: "One Direction Is Worse", body: "Eight sliders, one per compass point, each covering the 45\u{b0} of sky centred on it \u{2014} so S also covers SSE through SSW. A target is only ignored while it\u{2019}s below the line for the direction it\u{2019}s actually in, so something that spends the first half of the night behind the tree to the south and the rest of it clear to the west keeps the half you could really shoot. When that costs a target half an hour or more of otherwise good sky, it says so in that target\u{2019}s warnings, naming the direction. Sky View draws it too: the blocked sector steps inward, so the bite out of the dome is the shape of your actual sky. Dragging the main Blocked Horizon slider levels all eight again."),
            HelpSection(heading: "Saving More Than One Spot", body: "A front yard and a back yard are the same coordinates, the same forecast and the same Bortle class, and differ only in what is in the way \u{2014} so \u{201c}Save as a separate spot\u{201d} in Settings copies the current site under its own name, leaving you to set that copy\u{2019}s horizon. The copy becomes the site in use straight away, since describing it is the next thing you want to do. Saved sites list their horizon underneath the coordinates, which is the only line that tells two spots at one address apart. Searching for a place you have already saved keeps the name and horizon you gave it rather than resetting them, and if you have several saved at one address it keeps you on the one already in use."),
            HelpSection(heading: "Better Spot Nearby", body: "The section under the night list looks for a real place — a park, campground, beach, marina or boat ramp — within the distance you pick that's better to observe from than your site. The menu beside its title picks what \"better\" means: Darker sky or Open horizon. It never sends you further than you need to go: if somewhere closer is nearly as good as the best spot in range — within about a third of a magnitude, or 3° of horizon — it suggests the closer one, whichever distance you've picked. Anything listed underneath is closer still, just not as good."),
            HelpSection(heading: "Park Hours", body: "Most parks close at dusk, so check before you drive out. Where a park's hours are actually on record, the spot shows them — green if it stays open long enough after dark to be worth it tonight, amber if it closes at sunset or soon after dark. Where they aren't, there's a Check hours link to the park's website when one's known. Apple Maps doesn't share opening hours with apps, so hours come from OpenStreetMap (© OpenStreetMap contributors), which has them for only a minority of parks — no label means unknown, not open. Astronomy clubs often have arrangements to stay after hours at particular parks; it's worth asking one near you."),
            HelpSection(heading: "Darker Sky", body: "Looks for somewhere the sky should be noticeably darker than at your site. It shows the place's estimated Bortle class next to the same estimate for your site, and how many targets would score Good or better from there tonight compared with from here. Use This Spot switches planning to it and saves it next to your current site; Back to… switches home again. If the Bortle class you set for your site is two or more classes off the satellite estimate, the panel says so and offers to update it — the comparison is only as fair as that setting. It assumes the same blocked horizon as your site — if the spot is more open, lower it in Settings. And it can't know whether a park is open or safe after dark, so check before you go."),
            HelpSection(heading: "Open Horizon", body: "For when the sky's dark enough but trees or rooftops are in the way. Within a mile or few, it finds the most open ground in each nearby park or boat ramp from satellite land cover, and shows how low the horizon is there next to your own Blocked Horizon setting, which direction is clearest, and how much more of the sky you'd see. The Map link goes to that open patch itself, not the park's entrance. Use This Spot saves the spot with its estimated horizon. The satellite data knows where trees are but not how tall they are, so it assumes about 15 m — taller pines will block a few degrees more.")
        ]),

        HelpTopic(title: "Planning Settings", systemImage: "slider.horizontal.3", sections: [
            HelpSection(body: "These, in Settings → Planning, decide what counts as usable and what gets shown. They don't change any underlying astronomical calculation — just the thresholds applied to it."),
            HelpSection(heading: "Maximum Cloud Cover", body: "Hours with effective cloud cover above this get excluded — this is the number the green availability bars are actually tested against."),
            HelpSection(heading: "Minimum Darkness", body: "How far below the horizon the sun has to be before an hour counts as dark. Shown as a slider from twilight to fully astronomically dark, rather than raw degrees."),
            HelpSection(heading: "Minimum Altitude", body: "Targets below this altitude are excluded, on top of your blocked-horizon limits — useful for ruling out the murky, high-airmass sky near the horizon even where nothing's physically in the way."),
            HelpSection(heading: "Integration Goal", body: "The usable minutes a target needs to earn full marks on \"Time on Target.\" Set it to the session length you actually plan to shoot."),
            HelpSection(heading: "Hide Below Score", body: "A display filter on the target list only. Lowering it reveals more marginal targets without changing how anything is scored.")
        ]),

        HelpTopic(title: "Data Sources & Accuracy", systemImage: "antenna.radiowaves.left.and.right", sections: [
            HelpSection(body: "Everything this app shows comes from one of three places: a live weather forecast, astronomy computed locally on your Mac, or a catalogue built into the app itself. None of it is guessed."),
            HelpSection(heading: "Weather", body: "Cloud cover (split into low, mid and high layers), dew point, humidity, wind and gusts all come from Open-Meteo — a free forecast API that needs no account and no API key. One request is made per location each time you refresh; the age of the data currently in use is shown in the sidebar footer. If Open-Meteo can't be reached, the app quietly falls back to MET Norway (also free, also keyless), and the footer says \"backup source\" so a lower-fidelity forecast is never mistaken for the primary one — MET Norway doesn't publish wind gusts or a precipitation probability outside the Nordics, so those two figures become estimates in that case. To avoid hammering either service, automatic refreshes (app launch, changing a setting) are limited to once an hour; the Refresh button and Cmd-R always fetch immediately regardless."),
            HelpSection(heading: "Place Search", body: "Typing a place name in Settings → Location searches Open-Meteo's own geocoding endpoint, the same service as the weather, under the same terms. Typed coordinates skip this entirely."),
            HelpSection(heading: "Sky Overhead Panel", body: "The satellite image in the sidebar, under the night list, comes from NASA's GIBS Worldview service — free, no account, no API key. It's GOES-East's GeoColor product: true-colour by day, infrared cloud texture and city lights by night, so it stays readable after dark rather than going blank. It's refreshed alongside the weather, on the same once-an-hour throttle. GOES-East only sees the Americas, so outside that footprint the panel simply doesn't appear."),
            HelpSection(heading: "Better Spot Nearby: Open Horizon", body: "Trees, buildings, grass and water come from ESA WorldCover 2021, a 10 m global land-cover map made from Copernicus Sentinel-1 and Sentinel-2 satellite imagery (© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; CC BY 4.0). It's read directly from the dataset's free public copy, downloading only the small pieces around your site. From each candidate standing point, sight lines run out 600 m in 36 directions; the tallest obstruction along each sets how high the sky is blocked that way. Land cover doesn't record height, so trees count as 15 m, mangroves 6 m, buildings and paving 4 m and shrubs 2 m. The horizon shown is the altitude that clears three quarters of all directions."),
            HelpSection(heading: "Better Spot Nearby: Darker Sky", body: "Light pollution comes from NASA's Black Marble nightly radiance — satellite measurements of light shining up from the ground, with moonlight already removed — fetched from the same free GIBS service as the Sky Overhead panel. Six dates across the past year are combined to smooth out cloud gaps, then kept for 60 days. Sky glow at each candidate spot adds up every light within about 140 km, fading with distance to the power of 2.5 (Walker's law). One scale factor turns that into sky brightness; it was fitted once against a published light-pollution atlas at 18 places around Tampa, Denver and Anchorage, where the model agreed to within about a fifth of a magnitude. Treat the Bortle numbers as good to roughly half a class — much better at telling you which of two nearby places is darker than at naming either one exactly. Places themselves come from Apple Maps search, which needs no account or key."),
            HelpSection(heading: "Astronomy", body: "Every Sun and Moon position, every rise, set and twilight time, the Milky Way's position, and every target's altitude and azimuth is computed right on your Mac — no network request involved. The Sun uses the standard low-precision Meeus series, accurate to about 0.01°; the Moon uses a truncated ELP series, accurate to a few arcminutes in position and roughly a quarter hour in phase timing. Rise, set and twilight times are found by sampling altitude on a fixed grid and refining the crossing by bisection, which is also why circumpolar targets and polar summers work without any special-case logic."),
            HelpSection(heading: "The Catalogue", body: "The built-in target list is the complete Messier catalogue, 49 more non-Messier showpieces, and roughly 1,000 further NGC/IC objects — about 1,150 in total — compiled directly into the app rather than fetched from anywhere. Positions are J2000, quoted to about an arcminute."),
            HelpSection(heading: "OpenNGC", body: "The ~1,000 objects beyond Messier and the hand-picked showpieces come from OpenNGC (github.com/mattiaverga/OpenNGC), a maintained, openly licensed (CC-BY-SA-4.0) database of every NGC and IC object. They were selected by real brightness — not typed in from memory — with a script, kept in the app's own repository, that can be re-run if the upstream data ever improves."),
            HelpSection(heading: "Custom Targets", body: "Anything still missing can be added by hand from the Target Catalog window's + button — designation, type, position and size. A custom target is scored and planned exactly like a built-in one, and shows a small \"Custom\" badge in the catalog grid so it's easy to tell apart. Tap it again to edit or delete it."),
            HelpSection(heading: "Target Photographs", body: "Where a target's detail page or catalogue entry shows a photograph, it was pulled from Wikipedia at build time — Wikipedia only hosts appropriately licensed media, and the link beneath each photo credits the exact source article for full attribution and licence detail. Not every target has one.")
        ])
    ]
}

struct HelpView: View {
    @State private var selection: String? = HelpContent.topics.first?.id

    var body: some View {
        NavigationSplitView {
            List(HelpContent.topics, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.systemImage)
                    .tag(topic.id)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Palette.spaceBackground)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            if let topic = HelpContent.topics.first(where: { $0.id == selection }) {
                HelpTopicView(topic: topic)
            } else {
                EmptyStateView(title: "Select a Topic",
                               message: "Choose an item from the list at left to view its explanation.",
                               systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("Sky Bother User Guide")
        .frame(minWidth: 760, minHeight: 640)
    }
}

private struct HelpTopicView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: topic.systemImage)
                        .font(.scaled(.title, scale: uiTextScale).weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Text(topic.title)
                        .font(.scaled(.title, scale: uiTextScale).weight(.semibold))
                }

                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.scaled(.title3, scale: uiTextScale).weight(.semibold))
                        }
                        if !section.body.isEmpty {
                            Text(section.body)
                                .font(.scaled(.body, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !section.swatches.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(section.swatches) { swatch in
                                    HStack(alignment: .top, spacing: 9) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(swatch.color)
                                            .frame(width: 18, height: 14)
                                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.2)))
                                            .padding(.top, 2)
                                        Text(swatch.label)
                                            .font(.scaled(.callout, scale: uiTextScale))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelStyle()
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .spaceBackground()
        .navigationTitle(topic.title)
    }
}

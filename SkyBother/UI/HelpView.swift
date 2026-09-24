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
        HelpTopic(title: "Getting Started", systemImage: "sparkles", sections: [
            HelpSection(body: "Guided Setup has five steps: site, horizon, rig, goal and your first plan. Only the site is required; the other steps have defaults and a Skip button. Progress is saved, so quitting part-way resumes at the same step."),
            HelpSection(heading: "Advanced Setup", body: "“Advanced Setup…” at the top of Guided Setup opens every setting at once: exact coordinates and elevation, the horizon by direction, optics numbers, mount and filters, and all planning thresholds. It uses the same controls as Settings."),
            HelpSection(heading: "Running It Later", body: "Use “Guided Setup” at the foot of the night list, or “Run Guided Setup…” in Settings → Location. It isn’t available while the planner has unsaved changes.")
        ]),

        HelpTopic(title: "Scores & Verdicts", systemImage: "target", sections: [
            HelpSection(body: "Every night and every target gets a score from 0 to 100. It’s a weighted geometric mean of several factors, so one very poor factor — no clear sky, or no time above the horizon — pulls the score down hard."),
            HelpSection(heading: "Verdicts", body: "Scores fall into five verdicts, shown as a coloured tag:", swatches: [
                HelpSwatch(color: Palette.exceptional, label: "90 and above — Exceptional"),
                HelpSwatch(color: Palette.go, label: "75–89 — Excellent"),
                HelpSwatch(color: Palette.good, label: "60–74 — Good"),
                HelpSwatch(color: Palette.marginal, label: "45–59 — Marginal"),
                HelpSwatch(color: Palette.skip, label: "Below 45 — Poor")
            ]),
            HelpSection(heading: "Night Score", body: "Clear dark time (35%), sky clarity (30%), the Moon (25%) and conditions such as wind and dew (10%). Clear dark time and clarity come from the night’s best imaging window — its longest unbroken stretch of dark sky under your maximum cloud cover — measured against your integration goal."),
            HelpSection(heading: "Target Score", body: "Time on target (26%), sky darkness (18%), cloud cover (18%), framing (15%), detectability (14%) and altitude (9%). Night and target scores are independent: a good night can still be a poor one for a particular target.")
        ]),

        HelpTopic(title: "The Night Timeline", systemImage: "chart.bar.xaxis", sections: [
            HelpSection(heading: "Layers", body: "", swatches: [
                HelpSwatch(color: Palette.astronomical, label: "Background — sky darkness, from daylight through twilight to full dark"),
                HelpSwatch(color: Palette.cloud, label: "Grey from the top — forecast cloud; the deeper it reaches, the cloudier"),
                HelpSwatch(color: Palette.moonlight, label: "Pale wash and line near the bottom — moonlight and the Moon’s altitude")
            ]),
            HelpSection(heading: "Lines", body: "The dotted lines mark astronomical dusk and dawn. The red line marks the current time on tonight’s chart."),
            HelpSection(heading: "Hovering", body: "Point at the chart for the time, cloud, temperature, darkness and Moon altitude. With a target selected, its altitude is shown too, and whether it’s behind your blocked horizon in that direction."),
            HelpSection(heading: "Selected Target", body: "A selected target’s altitude curve, usable time and best window are drawn over the chart.")
        ]),

        HelpTopic(title: "Sky View", systemImage: "globe", sections: [
            HelpSection(body: "The sky as a dome: the zenith in the centre, the horizon at the rim, north at the top. Open it by clicking the small sky picture in the night’s summary on Home, “Sky View” in the planner, or “Show in Sky View” on a selected target. Back (or Esc) returns to where you came from; unsaved planner changes are kept. Sky View shows the plan but never changes it. Drag the divider to resize the side panel."),
            HelpSection(heading: "What’s Drawn", body: "The real sky at the chosen time, with twilight and moonlight brightening it as they would outside. Only the selected target is marked.", swatches: [
                HelpSwatch(color: Palette.go, label: "Selected target — green brackets around your rig’s frame, drawn to scale"),
                HelpSwatch(color: Palette.moonlight, label: "The Moon — at its true apparent size, when above the horizon")
            ]),
            HelpSection(heading: "Target Path", body: "The selected target’s full daily path around the pole: solid purple above the horizon, faint below it, amber where it passes through zenith risk."),
            HelpSection(heading: "Zenith Risk", body: "Alt-az mounts, including every smart telescope, rotate the field fastest overhead and some stall near the zenith. Time a target spends above the rig’s zenith limit (Settings → Equipment, default 80°) is marked in amber here, on target rows and on the plan. It doesn’t apply to equatorial mounts, and can be turned off in Settings → Equipment."),
            HelpSection(heading: "Frame and Roll", body: "“Frame” previews another rig’s frame without changing your active rig. “Camera roll” rotates the frame; the arrows beside it step one degree. The frame isn’t drawn below the horizon or within 2° of the zenith. On an alt-az mount it rotates through the night — that’s real field rotation."),
            HelpSection(heading: "Side Panel", body: "The time and the Moon (click it for the Moon card), then the selected target’s altitude, direction and whether it’s rising or setting. If it can’t be shot at that moment it says why — below the horizon, behind your blocked horizon, below your minimum altitude, not dark enough, or cloud — and when it can be. Below that is the plan, with the running block marked. Click a block to jump to its midpoint."),
            HelpSection(heading: "Playback", body: "“Play” (Space) runs the night in about 25 seconds; dragging the time bar pauses it. With Reduce Motion on, it steps 15 minutes at a time. “Follow planned targets” selects each planned target as its block starts, fading from one to the next, and fades the last one out when the plan ends; “Stay on selected target” keeps the selection.")
        ]),

        HelpTopic(title: "The Plan", systemImage: "list.number", sections: [
            HelpSection(body: "Home shows the night’s plan: the app’s suggestion — the best non-overlapping targets above your minimum score — or your own manual plan. Change it in the planner. When the window has room, the best unplanned targets are listed below the plan (“If it clears” on a clouded-out night); click one to see it in the Selected target panel."),
            HelpSection(heading: "Suggested or Manual", body: "A suggested plan updates with the forecast and your settings. It becomes manual only when you change it and press Done; a manual plan then stays as you left it. “Reset manual plan” replaces it with the current suggestion, with Undo until your next edit. Past nights’ plans are removed."),
            HelpSection(heading: "The Planner", body: "Open it with “Plan Session” or “Edit plan”. Click the date to switch to another night. The night, site and rig stay at the top, the timeline below them, then candidates on the left and the selected target on the right. Only the candidate list scrolls. Drag the divider to resize the panels."),
            HelpSection(heading: "Editing", body: "Drag a block to move it, or an edge to resize it; times snap to five minutes. Click a block, then: ← → move it, Shift-arrows change its end, Option-arrows its start, ↑ ↓ select the next block, Delete removes it. Nothing is saved until Done (⌘↩). Esc discards unsaved changes but keeps you in the planner; Cancel and Home leave it, asking first if there are changes."),
            HelpSection(heading: "Reordering", body: "Drag a block into its neighbour and the neighbour shortens. Keep going and it swaps to the other side. Dragging an edge shortens neighbours but never swaps them. Blocks never overlap."),
            HelpSection(heading: "Adding Targets", body: "Add puts a block in the longest free stretch, preferring time the target can actually be shot. The same target can have several blocks. The ✕ on a planned candidate, or “Remove from plan” in the Selected target panel, takes a target’s blocks out; the ✕ in the corner of a selected block (or Delete) removes just that block. If the list doesn’t have what you want, “Browse full catalog” at the end of it opens the catalog for the same night."),
            HelpSection(heading: "Candidates", body: "Filter by name, type, minimum usable time and “Fits my frame” (hides targets that overflow the frame or fill under a tenth of it). Selecting a candidate never changes the plan."),
            HelpSection(heading: "Longer Integration or More Targets", body: "Sets how the suggestion shares a short night. Longer integration gives each target up to your full integration goal and nothing under a third of it. More targets halves that, down to 20 minutes. It doesn’t change a manual plan."),
            HelpSection(heading: "Unshootable Time", body: "Blocks can cover time when the target isn’t up, dark or clear. That part is hatched and its minutes are totalled. A block whose target has no usable time at all is red. Clouded-out nights get no suggestion.")
        ]),

        HelpTopic(title: "Session View", systemImage: "play.circle", sections: [
            HelpSection(body: "“Session View” beside tonight’s plan on Home shows the plan for use at the telescope: what’s on now and how long is left, or what’s next and when it starts; what comes after; dew, cloud and wind; and the framing. It follows the clock, so there’s nothing to press — your telescope’s own app runs the night. The dim red-black screen is easy on dark-adapted eyes. It’s available for tonight only.")
        ]),

        HelpTopic(title: "Availability Bars", systemImage: "chart.xyaxis.line", sections: [
            HelpSection(body: "Each candidate has a bar on the same time axis as the timeline. It fills when the target is above your minimum altitude, the sky is dark enough, and cloud is under your maximum. Gaps are usually cloud. The line through it is the target’s altitude; the tick marks its best moment."),
            HelpSection(heading: "Figures", body: "Under each bar, always in this order: best time, peak altitude, how much of the frame it fills, and usable time. An amber triangle marks zenith risk.")
        ]),

        HelpTopic(title: "In Your Frame", systemImage: "camera.viewfinder", sections: [
            HelpSection(body: "A Digitized Sky Survey image centred on the target at your rig’s field of view, with your frame drawn on it. Green means it fits; dashed amber means it needs a mosaic. The cross marks the catalogued position — faint targets can be hard to see in the survey. Images are cached, so ones you’ve seen work offline."),
            HelpSection(heading: "Rig Presets", body: "Presets use published specifications. Check them against your own equipment; every number can be edited.")
        ]),

        HelpTopic(title: "Score Breakdown", systemImage: "list.bullet.rectangle", sections: [
            HelpSection(body: "“Why this score” on a target lists each factor with its rating, a bar, and the real figure behind it."),
            HelpSection(heading: "The −N Figure", body: "How many points that factor costs: the score if that factor were perfect, minus the actual score. The largest is the main limitation."),
            HelpSection(heading: "Detectability", body: "The target’s surface brightness against your sky background, allowing for f-ratio, integration time and filter. A target fainter than your sky can score near zero however clear the night; its warnings give both figures."),
            HelpSection(heading: "Framing", body: "Full marks for a target filling 30–80% of the frame’s long side. Targets under about 40 pixels across can’t be resolved and score near zero. Larger targets need a mosaic, which costs more on rigs that can’t make one.")
        ]),

        HelpTopic(title: "Cloud, Moon & Weather", systemImage: "cloud.moon", sections: [
            HelpSection(heading: "Cloud", body: "Cloud figures are weighted by layer: low cloud counts fully, mid-level 85%, high cirrus 50%. Your maximum cloud cover is checked against this figure."),
            HelpSection(heading: "Moon", body: "The Moon doesn’t shorten the night; it lowers each target’s score depending on phase, the Moon’s altitude and its distance from the target. A dual-band filter reduces the penalty for emission and planetary nebulae and supernova remnants."),
            HelpSection(heading: "Seeing", body: "Estimated from wind gusts only. Treat it as a hint."),
            HelpSection(heading: "Dew Risk", body: "From the gap between temperature and dew point: over 10°F Low, 6–10°F Moderate, 3–6°F High, 3°F or less Very High. Clear, calm nights raise it one step, because optics cool below the air. The rating is the worst hour of your session.", swatches: [
                HelpSwatch(color: Palette.dewRisk(.low), label: "Low — dew heater probably unnecessary"),
                HelpSwatch(color: Palette.dewRisk(.moderate), label: "Moderate — watch your optics"),
                HelpSwatch(color: Palette.dewRisk(.high), label: "High — dew heater recommended"),
                HelpSwatch(color: Palette.dewRisk(.veryHigh), label: "Very High — dew heater recommended")
            ])
        ]),

        HelpTopic(title: "Your Site", systemImage: "mappin.and.ellipse", sections: [
            HelpSection(heading: "Bortle Class", body: "1 (pristine) to 9 (city centre). It sets the sky brightness used for detectability, so it matters a lot. A light-pollution map will tell you yours."),
            HelpSection(heading: "Blocked Horizon", body: "How high trees, buildings and hills reach. Set one value all the way round, or use “Customize horizon by direction” for eight directions of 45° each. Targets are skipped only while they’re behind the direction they’re in. Returning to one value asks first."),
            HelpSection(heading: "More Than One Spot", body: "“Save as a separate spot” in Settings → Location copies the current site so you can give it its own horizon — for a front and back yard, say."),
            HelpSection(heading: "Better Spot Nearby", body: "Under the night list: finds a park, beach or similar within your chosen distance that has a darker sky or a more open horizon. It prefers a closer spot when it’s nearly as good. “Use This Spot” plans from there and saves it; “Back to…” returns. Check that a spot is open and safe after dark."),
            HelpSection(heading: "Park Hours", body: "Shown where OpenStreetMap has them: green if a park stays open well after dark, amber if it closes around sunset. No label means unknown."),
            HelpSection(heading: "Darker Sky", body: "Bortle estimates come from NASA satellite measurements of night lights, good to about half a class. If your site’s setting is two or more classes off the estimate, you’re offered the estimate."),
            HelpSection(heading: "Open Horizon", body: "Finds the most open ground in nearby parks from satellite land cover. Trees are assumed to be 15 m tall.")
        ]),

        HelpTopic(title: "Planning Settings", systemImage: "slider.horizontal.3", sections: [
            HelpSection(heading: "Goal", body: "Quick session, Deep integration and Variety each set the integration goal and plan emphasis. Changing either value makes it Custom."),
            HelpSection(heading: "Maximum Cloud Cover", body: "Hours cloudier than this don’t count. Around 20% works well."),
            HelpSection(heading: "Minimum Darkness", body: "The sun altitude at which the sky counts as dark. −18° is full astronomical darkness."),
            HelpSection(heading: "Minimum Altitude", body: "Targets lower than this are skipped, even where the horizon is open."),
            HelpSection(heading: "Integration Goal", body: "The usable time a target needs for full marks on time on target."),
            HelpSection(heading: "Hide Below Score", body: "Targets under this score are left out of lists and suggestions. It doesn’t change any score."),
            HelpSection(heading: "UI Scale", body: "Under the night list. With Auto on, the interface sizes itself to the window. Turn Auto off to set it yourself."),
            HelpSection(heading: "Nights Ahead", body: "How many nights to plan. Cloud forecasts beyond about a week are unreliable.")
        ]),

        HelpTopic(title: "The Catalog", systemImage: "photo.on.rectangle.angled", sections: [
            HelpSection(body: "“Catalog” in the toolbar (⌘K). Every target is scored for one night — the one you’re planning or viewing, or another from the Night menu. Cards show the score, verdict, usable time and framing."),
            HelpSection(heading: "Sorting and Filters", body: "Sort by best on the night or longest window; filter to Good or better, Fits my frame, or a minimum usable time."),
            HelpSection(heading: "Target Page", body: "Shows how the target does on the night, then “Add to …’s plan” (opens the planner with it added; nothing is saved until Done) and “View on …” (shows it in the main window). Pictures: your frame on the sky survey, and a photograph or a survey close-up."),
            HelpSection(heading: "Custom Targets", body: "“Add Custom Target” adds anything missing. Custom targets are scored like any other; click one to edit or delete it.")
        ]),

        HelpTopic(title: "Data Sources", systemImage: "antenna.radiowaves.left.and.right", sections: [
            HelpSection(heading: "Weather", body: "Open-Meteo, free and keyless. In the US and southern Canada the cloud totals come from NOAA’s National Blend of Models. If Open-Meteo is unreachable, MET Norway is used and the sidebar says “backup source”. Automatic refreshes happen at most hourly; Refresh (⌘R) always fetches."),
            HelpSection(heading: "Astronomy", body: "Sun, Moon and target positions and all rise, set and twilight times are computed on your Mac. The Sun is accurate to about 0.01°, the Moon to a few arcminutes."),
            HelpSection(heading: "Catalog", body: "About 1,150 targets: the Messier catalogue, 49 other showpieces, and about 1,000 NGC/IC objects from OpenNGC (CC-BY-SA-4.0). Positions are J2000."),
            HelpSection(heading: "Images", body: "Framing images: Digitized Sky Survey (STScI/NASA), colour by CDS. Photographs: Wikipedia, credited under each. Satellite clouds: NASA GIBS, GOES-East GeoColor (Americas only). Sky View star map: NASA Goddard SVS Deep Star Maps 2020, from Gaia DR2, Hipparcos-2 and Tycho-2. Moon: NASA SVS CGI Moon Kit, from Lunar Reconnaissance Orbiter data."),
            HelpSection(heading: "Nearby Spots", body: "Places: Apple Maps. Night lights: NASA Black Marble. Land cover: ESA WorldCover 2021 (© ESA WorldCover project / Copernicus Sentinel data, CC BY 4.0). Park hours: © OpenStreetMap contributors.")
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

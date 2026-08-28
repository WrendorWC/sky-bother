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
        HelpTopic(title: "Scores & verdicts", systemImage: "target", sections: [
            HelpSection(body: "Every night and every target gets a 0–100 score, shown in the coloured circle. It is a weighted geometric mean of several 0–1 factors, not a plain average — geometric because a single near-zero factor (no clear sky, no time above the horizon) should sink the score, not get smoothed away by the others being fine."),
            HelpSection(heading: "The coloured tag", body: "The score is bucketed into five verdicts, shown as the pill next to the date or target name. Exceptional gets a deliberate gold glow — it's meant to be rare and to stand out from an ordinary good night:", swatches: [
                HelpSwatch(color: Palette.exceptional, label: "90 and up — Exceptional"),
                HelpSwatch(color: Palette.go, label: "75–89 — Excellent"),
                HelpSwatch(color: Palette.good, label: "60–74 — Good"),
                HelpSwatch(color: Palette.marginal, label: "45–59 — Marginal"),
                HelpSwatch(color: Palette.skip, label: "Under 45 — Poor")
            ]),
            HelpSection(heading: "Night score vs. target score", body: "A night's score weighs clear dark time (35%), sky clarity (30%), the moon (25%) and conditions like wind and dew (10%). A target's score weighs time on target (26%), sky darkness (18%), clear sky (18%), how well it fills your frame (15%), how detectable it is against your sky (14%) and altitude (9%). They're separate numbers on purpose — a night can be great while a specific target is a poor fit for it, or the other way around.")
        ]),

        HelpTopic(title: "The night timeline", systemImage: "chart.bar.xaxis", sections: [
            HelpSection(body: "This is the chart the whole app is built around — every target's availability bar underneath shares its exact time axis, so reading straight down a column tells you what's up at any given moment."),
            HelpSection(heading: "What the layers mean", body: "", swatches: [
                HelpSwatch(color: Palette.astronomical, label: "Background — real sky darkness, from daylight blue through civil, nautical and astronomical twilight to black"),
                HelpSwatch(color: Palette.cloud, label: "Grey, coming down from the top — forecast cloud cover; the deeper it reaches, the cloudier that hour"),
                HelpSwatch(color: Palette.moonlight, label: "Pale wash over the background, plus the traced line near the bottom — moonlight and the moon's altitude through the night")
            ]),
            HelpSection(heading: "The dotted lines and the red line", body: "The two dotted verticals mark astronomical dusk and dawn — the boundary this app treats as \"properly dark\". The thin red line is simply the current time, when tonight is in view."),
            HelpSection(heading: "Hovering", body: "Hold the pointer anywhere on the chart for an exact readout: time, cloud %, temperature, how dark it is (as a percentage), and the moon's altitude if it's up."),
            HelpSection(heading: "When a target is selected", body: "Pick a target from the list and this same chart overlays its altitude curve (the bold white line), its usable windows (tinted in its own score colour) and its single best window (the dashed box) directly on top of the sky and cloud layers — so you can read straight up from \"this is the best window\" to \"and here's why\" without switching to a second chart.")
        ]),

        HelpTopic(title: "Target availability bars", systemImage: "chart.xyaxis.line", sections: [
            HelpSection(body: "Each row in the target list has its own thin bar sharing the night timeline's axis. Underneath it, a faint white line traces the target's altitude rising and setting through the night — that part is just geometry, and it's drawn even for hours the target isn't usable."),
            HelpSection(heading: "What the green fill means", body: "A stretch is filled in — in the same colour as the target's score badge — only where all three of these are true at once: the target is above your minimum altitude, the sky is dark enough for your Settings threshold, and the forecast cloud cover is under your \"Maximum cloud cover\" limit. It's a genuine three-way AND, evaluated every five minutes."),
            HelpSection(heading: "Why there can be gaps", body: "Altitude only rises then falls once a night, and once astronomical dark starts it stays dark — neither of those un-does itself midway through the night. Cloud cover is the one factor that isn't one-directional: if the forecast has it dipping under your threshold, climbing back over, then dropping again, you'll see that as separate green blocks with real gaps between them, not a rendering glitch. The bright vertical tick inside a bar marks that target's single best moment."),
            HelpSection(heading: "Double Cluster, for example", body: "If tonight's Double Cluster bar shows one solid green block, it's up, it's dark, and the forecast stays clear underneath it that whole time. Two blocks with a gap between them means the same target and the same darkness, but the forecast has a cloudier patch sitting in between — check the main timeline above it at that same clock time and you'll see the grey cloud layer reaching further down.")
        ]),

        HelpTopic(title: "\"In your frame\"", systemImage: "camera.viewfinder", sections: [
            HelpSection(body: "This panel, on a target's detail page, answers the question a magnitude number can't: will it actually look like something through your specific telescope and sensor?"),
            HelpSection(heading: "Reading it", body: "The ellipse (or photo, when the built-in catalogue has one) is the target's real catalogued size, drawn to scale against your rig's actual field of view — the rectangle. A solid green rectangle means it fits comfortably; a dashed amber one means it's oversized for a single frame and would need a mosaic, or is being shown anyway because you've allowed oversized targets in Settings. The number under the target is its apparent size in the sky; the number in the corner of the frame is your field of view in degrees."),
            HelpSection(heading: "The photo", body: "Where one is available, it's pulled from Wikipedia and clipped to the same ellipse — a real look at the object, not just a shape. The link under the panel credits the source; not every target in the catalogue has one.")
        ]),

        HelpTopic(title: "Score breakdown", systemImage: "list.bullet.rectangle", sections: [
            HelpSection(body: "\"Why this score\" on a target's page lists every factor that fed its geometric mean, each with its own Exceptional-through-Poor rating and a bar from 0–100%. A short line under each bar explains the specific number behind it — the actual usable minutes, the actual surface brightness, and so on."),
            HelpSection(heading: "The \"−N\" next to a factor", body: "That number is real, not invented: it's the score with that one factor set to perfect (1.0), re-run through the same geometric mean, minus the actual score. It's how many points that specific factor is genuinely costing you right now — not a fixed share of its weight, since in a geometric mean what one factor costs depends on what every other factor is doing too. The \"Main limitation\" line at the top is simply whichever factor's −N is largest."),
            HelpSection(heading: "\"Why not recommended\"", body: "Marginal and poor targets get a short bullet list pulled from whichever factors are actually weakest, in their own words — not a canned excuse."),
            HelpSection(heading: "Detectability", body: "This is surface brightness against your sky, not just how bright the target's catalogue magnitude says it is: its light is spread over its full catalogued size and compared against your Bortle-class sky background, adjusted for your f-ratio, integration time and any filter. It's why the same galaxy can score well from a dark site and near zero from a city, even on an identical clear night."),
            HelpSection(heading: "Framing", body: "Full marks go to a target filling 30–80% of your frame's long side. Smaller wastes the sensor; larger needs a mosaic, penalised lightly if your rig supports one and heavily if it doesn't.")
        ]),

        HelpTopic(title: "Cloud, moon & weather numbers", systemImage: "cloud.moon", sections: [
            HelpSection(heading: "Cloud percentage", body: "Every cloud % you see — in the sidebar, the night header, the hover readout — is an \"effective\" figure, not the raw forecast. Open-Meteo reports total cloud cover split into low, mid and high layers; this app weighs low cloud at full strength, mid-layer at 85%, and thin high cirrus at only 50%, since cirrus barely dents an image while low cloud kills it outright. Your \"Maximum cloud cover\" setting is compared against this effective number."),
            HelpSection(heading: "Moon", body: "A bright moon doesn't shorten the night — darkness windows are set by the sun alone — so the moon is applied instead as a per-target quality penalty. It scales with phase raised to the power 2.2 (a half moon is far less than half as bright as a full one), with the moon's own altitude, and with how far the target sits from it. A dual-band filter cuts that penalty to 40% and adds contrast on emission and planetary nebulae and supernova remnants — which is why the app will send you out after the Crescent Nebula under a gibbous moon and tell you to skip a galaxy the same night."),
            HelpSection(heading: "Seeing & dew", body: "Seeing is a rough proxy from surface wind gusts — real seeing depends on the jet stream, which no free forecast exposes, so treat it as a hint. Dew risk is flagged when the forecast dew-point spread (air temperature minus dew point) drops close to zero, since that's when a corrector plate or lens starts fogging.")
        ]),

        HelpTopic(title: "Bortle class & your site", systemImage: "mappin.and.ellipse", sections: [
            HelpSection(body: "Bortle class (1 pristine, 9 inner-city) is the single most consequential number in the app, set by hand in Settings → Location because no free API can measure your actual sky. It sets the zenith sky brightness used everywhere detectability is judged — it's the reason the exact same galaxy can be a non-starter from a Bortle 8 backyard and an easy target from a Bortle 4 field twenty miles out."),
            HelpSection(heading: "Blocked horizon", body: "The altitude below which trees, houses or hills block your actual view. Anything that never climbs above it is treated as not observable at all, regardless of what the raw ephemeris says.")
        ]),

        HelpTopic(title: "Planning settings", systemImage: "slider.horizontal.3", sections: [
            HelpSection(body: "These, in Settings → Planning, control what counts as usable and what gets shown — they don't change any astronomy, only the thresholds applied to it."),
            HelpSection(heading: "Maximum cloud cover", body: "Hours with effective cloud above this are written off — this is the number the green availability bars are tested against."),
            HelpSection(heading: "Minimum darkness", body: "How far below the horizon the sun must be before an hour counts as dark, expressed as a slider from twilight-ish to fully astronomically dark rather than raw degrees."),
            HelpSection(heading: "Minimum altitude", body: "Targets below this are ignored, on top of your blocked-horizon limit — useful for cutting off the murky, high-airmass sky near the horizon even where nothing physically blocks it."),
            HelpSection(heading: "Integration goal", body: "The number of usable minutes a target needs to earn full marks on the \"time on target\" factor — set it to whatever session length you actually plan to run."),
            HelpSection(heading: "Hide below score", body: "Purely a display filter on the target list — lowering it shows more marginal targets without changing how anything is scored.")
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
                EmptyStateView(title: "Pick a topic",
                               message: "Choose something from the list to see what it means.",
                               systemImage: "questionmark.circle")
            }
        }
        .navigationTitle("Sky Bother Help")
        .frame(minWidth: 760, minHeight: 640)
    }
}

private struct HelpTopicView: View {
    var topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: topic.systemImage)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Text(topic.title)
                        .font(.title.weight(.semibold))
                }

                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.title3.weight(.semibold))
                        }
                        if !section.body.isEmpty {
                            Text(section.body)
                                .font(.body)
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
                                            .font(.callout)
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

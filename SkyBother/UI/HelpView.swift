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
            HelpSection(body: "Every night and every target is assigned a score from 0 to 100, displayed within the coloured circle. This score is calculated as a weighted geometric mean of several factors, each expressed on a 0 to 1 scale, rather than as a simple average. A geometric mean is used because a single near-zero factor — for example, no clear sky, or no time above the horizon — reduces the overall score substantially, rather than being masked by favourable values in the remaining factors."),
            HelpSection(heading: "The Coloured Tag", body: "Each score is grouped into one of five verdicts, displayed as a coloured pill beside the relevant date or target name. All five verdicts occupy a single red-to-green scale, so colour carries a consistent meaning throughout the application: red indicates a poorer result, and green indicates a better one. The Exceptional verdict uses a brighter, more saturated green with an added glow, reserved deliberately for the rare night or target that stands well above an ordinary good result:", swatches: [
                HelpSwatch(color: Palette.exceptional, label: "90 and above — Exceptional"),
                HelpSwatch(color: Palette.go, label: "75–89 — Excellent"),
                HelpSwatch(color: Palette.good, label: "60–74 — Good"),
                HelpSwatch(color: Palette.marginal, label: "45–59 — Marginal"),
                HelpSwatch(color: Palette.skip, label: "Below 45 — Poor")
            ]),
            HelpSection(heading: "Night Score vs. Target Score", body: "A night's score is weighted as follows: clear dark time (35%), sky clarity (30%), the moon (25%), and conditions such as wind and dew (10%). A target's score is weighted differently: time on target (26%), sky darkness (18%), clear sky (18%), how well the target fills the frame (15%), how detectable it is against the sky background (14%), and altitude (9%). These two figures are calculated independently and by design — a night may be excellent overall while a specific target remains a poor match for it, or the reverse may be true.")
        ]),

        HelpTopic(title: "The Night Timeline", systemImage: "chart.bar.xaxis", sections: [
            HelpSection(body: "This chart forms the foundation of the entire application. Every target's availability bar beneath it shares the same time axis, so reading directly down any column indicates precisely what is visible at that moment."),
            HelpSection(heading: "What the Layers Mean", body: "", swatches: [
                HelpSwatch(color: Palette.astronomical, label: "Background — actual sky darkness, progressing from daylight blue through civil, nautical and astronomical twilight to black"),
                HelpSwatch(color: Palette.cloud, label: "Grey layer descending from the top — forecast cloud cover; the further it extends downward, the cloudier that hour is expected to be"),
                HelpSwatch(color: Palette.moonlight, label: "Pale wash over the background, together with the traced line near the bottom — moonlight and the moon's altitude throughout the night")
            ]),
            HelpSection(heading: "The Dotted Lines and the Red Line", body: "The two dotted vertical lines mark astronomical dusk and astronomical dawn — the boundary this application treats as genuine darkness. The thin red line indicates the current time, when tonight's plan is being viewed."),
            HelpSection(heading: "Hovering", body: "Holding the pointer over any point on the chart displays an exact readout, including the time, cloud percentage, temperature, degree of darkness (expressed as a percentage), and the moon's altitude, if it is above the horizon."),
            HelpSection(heading: "When a Target Is Selected", body: "Selecting a target from the list overlays its altitude curve, its usable windows and its single best window directly onto the sky and cloud layers, all drawn in the application's one accent colour so the selection reads the same way here as it does everywhere else. This allows the best window, and the reasoning behind it, to be read from a single chart without consulting a separate view.")
        ]),

        HelpTopic(title: "Target Availability Bars", systemImage: "chart.xyaxis.line", sections: [
            HelpSection(body: "Each row in the target list contains its own thin bar, sharing the night timeline's axis. Beneath it, a faint white line traces the target's altitude as it rises and sets throughout the night; this line reflects geometry alone and is drawn even during hours when the target is not usable."),
            HelpSection(heading: "What the Green Fill Means", body: "A segment of the bar is filled, using the same colour as the target's score badge, only when all three of the following conditions are met simultaneously: the target is above the configured minimum altitude, the sky is dark enough to satisfy the configured darkness threshold, and the forecast cloud cover is below the configured maximum cloud cover limit. This is a genuine three-way logical AND, evaluated at five-minute intervals."),
            HelpSection(heading: "Why There Can Be Gaps", body: "Altitude rises and then falls only once per night, and once astronomical darkness begins, it persists — neither condition reverses partway through the night. Cloud cover, however, is not one-directional: if the forecast shows cover dipping below the threshold, rising back above it, and then dropping again, this will appear as separate green segments with genuine gaps between them, rather than a rendering error. The bright vertical tick within a bar marks that target's single best moment."),
            HelpSection(heading: "Example: Double Cluster", body: "If tonight's Double Cluster bar shows a single solid green block, the target is above the horizon, the sky is dark, and the forecast remains clear for the duration shown. Two blocks separated by a gap indicate the same target under the same darkness conditions, but with a forecast cloud patch occurring in between. Consulting the main timeline above, at the corresponding time, will show the grey cloud layer extending further downward.")
        ]),

        HelpTopic(title: "\"In Your Frame\"", systemImage: "camera.viewfinder", sections: [
            HelpSection(body: "This panel, located on each target's detail page, addresses a question that a magnitude figure alone cannot answer: whether the target will produce a meaningful image through the specific telescope and sensor configured."),
            HelpSection(heading: "Reading It", body: "The ellipse (or photograph, where the built-in catalogue provides one) represents the target's actual catalogued size, drawn to scale against the configured rig's field of view, shown as the rectangle. A solid green rectangle indicates the target fits comfortably within a single frame. A dashed amber rectangle indicates the target is oversized for a single frame and would require a mosaic, or is being displayed regardless because oversized targets have been permitted in Settings. The figure beneath the target indicates its apparent size in the sky; the figure in the corner of the frame indicates the configured field of view, in degrees."),
            HelpSection(heading: "The Photograph", body: "Where available, the photograph is retrieved from Wikipedia and clipped to the same ellipse, providing an actual view of the object rather than a schematic shape. The link beneath the panel credits the source. Not every target in the catalogue has an associated photograph.")
        ]),

        HelpTopic(title: "Score Breakdown", systemImage: "list.bullet.rectangle", sections: [
            HelpSection(body: "The \"Why This Score\" section on each target's page lists every factor contributing to its geometric mean, each with its own rating, ranging from Exceptional to Poor, and a bar scaled from 0 to 100 percent. A brief line beneath each bar explains the specific figure behind it, such as the actual usable minutes or the actual surface brightness."),
            HelpSection(heading: "The \"−N\" Value Beside Each Factor", body: "This figure is calculated, not estimated: it represents the score obtained when that single factor is set to its perfect value (1.0) and the geometric mean is recalculated, minus the actual score. It therefore indicates precisely how many points that specific factor is presently costing — not a fixed share of its overall weight, since in a geometric mean the cost of one factor depends on the values of every other factor as well. The \"Main Limitation\" line at the top identifies whichever factor carries the largest −N value."),
            HelpSection(heading: "\"Why Not Recommended\"", body: "Targets rated Marginal or Poor are accompanied by a short list of reasons, drawn from whichever factors are genuinely weakest, rather than a generic explanation."),
            HelpSection(heading: "Detectability", body: "This factor measures surface brightness against the sky background, rather than simply the brightness indicated by the target's catalogue magnitude. Its light is distributed across its full catalogued size and compared against the configured Bortle-class sky background, adjusted for f-ratio, integration time, and any filter in use. This is why the same galaxy may score well from a dark-sky site and near zero from within a city, even under an otherwise identical clear sky."),
            HelpSection(heading: "Framing", body: "Full marks are awarded to a target filling between 30 and 80 percent of the frame's long side. A smaller target under-uses the sensor; a larger target requires a mosaic, which is penalised lightly if the configured rig supports mosaicking and heavily if it does not.")
        ]),

        HelpTopic(title: "Cloud, Moon & Weather Numbers", systemImage: "cloud.moon", sections: [
            HelpSection(heading: "Cloud Percentage", body: "Every cloud percentage displayed — in the sidebar, the night header, and the hover readout — is an effective figure rather than the raw forecast value. Open-Meteo reports total cloud cover divided into low, mid and high layers; this application weighs low cloud at full strength, mid-level cloud at 85 percent, and thin high cirrus at only 50 percent, since cirrus has minimal impact on an image while low cloud degrades it substantially. The configured \"Maximum Cloud Cover\" setting is compared against this effective figure."),
            HelpSection(heading: "Moon", body: "A bright moon does not shorten the night, since darkness windows are determined by the sun alone; the moon is instead applied as a per-target quality penalty. This penalty scales with lunar phase raised to the power of 2.2 (a half moon is considerably less than half as bright as a full moon), with the moon's own altitude, and with the target's angular separation from it. A dual-band filter reduces this penalty to 40 percent and adds contrast for emission nebulae, planetary nebulae and supernova remnants — which is why the application may recommend the Crescent Nebula under a gibbous moon while advising against a galaxy on the same night."),
            HelpSection(heading: "Seeing & Dew", body: "Seeing is approximated from surface wind gusts. Actual seeing depends on jet stream conditions, which no free forecast source exposes, so this figure should be treated as an indication rather than a precise measurement. Dew risk is flagged when the forecast dew-point spread — air temperature minus dew point — approaches zero, as this is the point at which a corrector plate or lens typically begins to fog.")
        ]),

        HelpTopic(title: "Bortle Class & Your Site", systemImage: "mappin.and.ellipse", sections: [
            HelpSection(body: "Bortle class — ranging from 1 (pristine) to 9 (inner-city) — is the single most consequential figure in the application. It is entered manually in Settings → Location, since no free API can measure an actual sky. This figure sets the zenith sky brightness used throughout all detectability calculations, and is the reason the same galaxy may be unviable from a Bortle 8 backyard while remaining an easy target from a Bortle 4 site twenty miles away."),
            HelpSection(heading: "Blocked Horizon", body: "This is the altitude below which trees, structures or terrain obstruct the actual view. Any target that never rises above this altitude is treated as unobservable, regardless of what the raw ephemeris indicates.")
        ]),

        HelpTopic(title: "Planning Settings", systemImage: "slider.horizontal.3", sections: [
            HelpSection(body: "These settings, found in Settings → Planning, determine what is treated as usable and what is displayed. They do not alter any underlying astronomical calculation — only the thresholds applied to it."),
            HelpSection(heading: "Maximum Cloud Cover", body: "Hours with effective cloud cover above this threshold are excluded. This is the figure against which the green availability bars are tested."),
            HelpSection(heading: "Minimum Darkness", body: "This setting determines how far below the horizon the sun must be before an hour is counted as dark. It is expressed as a slider ranging from twilight to fully astronomically dark, rather than as raw degrees."),
            HelpSection(heading: "Minimum Altitude", body: "Targets below this altitude are excluded, in addition to the configured blocked-horizon limit. This is useful for excluding the murky, high-airmass sky near the horizon, even where no physical obstruction is present."),
            HelpSection(heading: "Integration Goal", body: "This is the number of usable minutes a target requires to earn full marks on the \"Time on Target\" factor. It should be set to the session length actually planned."),
            HelpSection(heading: "Hide Below Score", body: "This is purely a display filter applied to the target list. Lowering it reveals more marginal targets without altering how anything is scored.")
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

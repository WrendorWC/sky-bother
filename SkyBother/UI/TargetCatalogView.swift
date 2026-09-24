import SwiftUI

/// A browsable reference catalog — every target in the built-in list, with a
/// photo, so you know what you're actually pointing at before you commit a
/// night to it. Independent of any night's plan: this is "what's out
/// there", not "what's up tonight" — and "what's out there" means the whole
/// sky, not just the half of it visible from north of the tropics. This
/// used to filter out anything below -55° declination (the reasoning being
/// that a handful of deep-southern showpieces like the Magellanic Clouds
/// never clear a northern horizon), which quietly excluded a real chunk of
/// the catalogue once the ~1,000-object OpenNGC extension folded in
/// hundreds more deep-southern targets — invisible from a northern site,
/// but exactly what a southern-hemisphere observer would open this window
/// looking for. The actual nightly plan was never filtered this way (it
/// already only shows what genuinely clears your own horizon); the browse
/// catalog shouldn't assume a hemisphere either.
struct TargetCatalogView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    @State private var query = CatalogQuery()
    @State private var selected: Target?
    @State private var editorContext: CustomTargetEditorContext?
    /// The night the catalog is scoring against, when chosen here. Until
    /// then it follows the night being planned, or the one open on Home.
    @State private var chosenNightID: Date?

    private var customTargetIDs: Set<String> {
        Set(state.customTargets.map(\.id))
    }

    /// The night every card is judged against.
    private var night: NightPlan? {
        let id = chosenNightID ?? state.nightBeingPlanned?.id ?? state.selectedNightID
        return state.plans.first { $0.id == id } ?? state.plans.first
    }

    /// That night's results, straight from the planner's existing run — the
    /// catalog never scores anything itself, so it can't disagree with Home.
    private var scored: [String: TargetPlan] {
        Dictionary((night?.targets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var effectiveQuery: CatalogQuery {
        var effective = query
        if night == nil {
            if effective.sort.needsNight { effective.sort = .alphabetical }
            effective.goodOnly = false
            effective.fitsFrameOnly = false
            effective.minimumUsableHours = 0
        }
        return effective
    }

    private var targets: [Target] {
        effectiveQuery.apply(to: BuiltInCatalog.all + state.customTargets, scored: scored)
    }

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    var body: some View {
        let scored = self.scored
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(targets) { target in
                        let isCustom = customTargetIDs.contains(target.id)
                        TargetCatalogCell(target: target, isCustom: isCustom,
                                          result: scored[target.id], hasNight: night != nil)
                            .onTapGesture {
                                if isCustom {
                                    editorContext = CustomTargetEditorContext(existing: target)
                                } else {
                                    selected = target
                                }
                            }
                    }
                }
                .padding(20)
            }
        }
        .spaceBackground()
        .navigationTitle("Target Catalog")
        .frame(minWidth: 760, minHeight: 560)
        .sheet(item: $selected) { target in
            TargetCatalogDetail(target: target, night: night)
                .environmentObject(state)
        }
        .sheet(item: $editorContext) { context in
            CustomTargetEditor(existing: context.existing)
        }
        .onAppear { applyRequest() }
        .onChange(of: state.catalogRequest) { _, _ in applyRequest() }
    }

    /// Opened for a particular night — from the planner, say — the catalog
    /// switches to it, and to its search if it brought one.
    private func applyRequest() {
        guard let request = state.catalogRequest else { return }
        state.catalogRequest = nil
        if let nightID = request.nightID { chosenNightID = nightID }
        if let search = request.search { query.search = search }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search the catalog", text: $query.search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.panelBorder))
                .frame(maxWidth: 280)

                Menu {
                    Button("All Types") { query.types.removeAll() }
                    Divider()
                    ForEach(TargetType.allCases) { type in
                        Toggle(type.displayName, isOn: Binding(
                            get: { query.types.contains(type) },
                            set: { isOn in
                                if isOn { query.types.insert(type) } else { query.types.remove(type) }
                            }))
                    }
                } label: {
                    Label(query.types.isEmpty ? "All Types" : "\(query.types.count) Types",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
                .scaledMenuStyle(uiTextScale)

                Menu {
                    Picker("Sort by", selection: $query.sort) {
                        ForEach(CatalogQuery.Sort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(effectiveQuery.sort.rawValue, systemImage: "arrow.up.arrow.down.circle")
                }
                .scaledMenuStyle(uiTextScale)

                Spacer()

                Text("\(targets.count) target\(targets.count == 1 ? "" : "s")")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)

                Button {
                    editorContext = CustomTargetEditorContext(existing: nil)
                } label: {
                    Label("Add Custom Target", systemImage: "plus.circle.fill")
                        .font(.scaled(.callout, scale: uiTextScale))
                }
                .help("Add a target that isn't in the catalog")
            }

            // The night every card is judged against, and the filters that
            // only make sense once there is one.
            HStack(spacing: 14) {
                Menu {
                    ForEach(state.plans) { plan in
                        Button {
                            chosenNightID = plan.id
                        } label: {
                            Text("\(nightName(plan)) · \(Int(plan.score.rounded())) \(plan.verdict.rawValue)")
                        }
                    }
                } label: {
                    Label(night.map { "Night: \(nightName($0))" } ?? "No nights yet", systemImage: "moon.stars")
                }
                .scaledMenuStyle(uiTextScale)
                .disabled(state.plans.isEmpty)
                .help("The night each card is scored for")

                Toggle("Good or better", isOn: $query.goodOnly)
                    .toggleStyle(.checkbox)
                    .help("Only targets rated Good, Excellent or Exceptional on this night")
                Toggle("Fits my frame", isOn: $query.fitsFrameOnly)
                    .toggleStyle(.checkbox)
                    .help("Hide targets that overflow the frame or are tiny in it (under 10% of the long side)")
                Menu {
                    Picker("Usable for at least", selection: $query.minimumUsableHours) {
                        Text("Any time").tag(0.0)
                        Text("1 hour").tag(1.0)
                        Text("2 hours").tag(2.0)
                        Text("3 hours").tag(3.0)
                        Text("4 hours").tag(4.0)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(query.minimumUsableHours == 0 ? "Any usable time" : "At least \(Int(query.minimumUsableHours))h usable",
                          systemImage: "clock")
                }
                .scaledMenuStyle(uiTextScale)

                Spacer()

                if night != nil {
                    Text("\(state.site.name) · \(state.rig.name)")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .disabled(night == nil)
        }
        .font(.scaled(.callout, scale: uiTextScale))
        .padding(16)
    }

    private func nightName(_ plan: NightPlan) -> String {
        "\(Format.weekday(plan.date, in: plan.timeZone)) \(Format.dayAndMonth(plan.date, in: plan.timeZone))"
    }
}

/// Identifies one presentation of the custom-target editor sheet — `nil`
/// existing means "adding new," a value means "editing that target." Wrapped
/// in its own `Identifiable` rather than using `Target?` directly as the
/// `sheet(item:)` driver, since `nil` there would mean "no sheet" instead of
/// "new target."
private struct CustomTargetEditorContext: Identifiable {
    let id = UUID()
    var existing: Target?
}

private struct TargetCatalogCell: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var target: Target
    var isCustom: Bool = false
    /// This target on the catalog's night; nil when it has no usable time.
    var result: TargetPlan?
    var hasNight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Held to the column's width: a panorama like the Veil's photo
            // otherwise widened its card over the next one.
            TargetThumbnail(designation: target.designation)
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: 140)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.panelBorder))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: target.type.symbolName)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(Palette.accent)
                    Text(target.displayName)
                        .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                        .lineLimit(1)
                    if isCustom {
                        Text("Custom")
                            .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Palette.accent.opacity(0.22), in: Capsule())
                            .foregroundStyle(Palette.accent)
                    }
                }
                Text("\(target.designation) · \(target.constellationName)")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if hasNight {
                // One height whether there's a result or not, so the grid's
                // rows stay even.
                nightLine
                    .frame(maxWidth: .infinity, minHeight: 44 * uiTextScale, alignment: .topLeading)
            }
        }
        .padding(9)
        .panelStyle(cornerRadius: 12)
        .contentShape(Rectangle())
    }

    /// Score, verdict and usable time on the night, then framing — the same
    /// values, in the same words, as Home's panel for this target.
    @ViewBuilder
    private var nightLine: some View {
        if let result {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ScoreBadge(score: result.score, size: 24)
                    Text("\(result.verdict.rawValue) · \(result.usableHoursText)")
                        .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                        .foregroundStyle(Palette.verdict(result.verdict))
                        .lineLimit(1)
                }
                Text(result.fit.framingNote)
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .hoverTooltip(result.fit.framingNote)
            }
        } else {
            Label("No usable time this night", systemImage: "moon.zzz")
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

struct TargetCatalogDetail: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var state: AppState
    var target: Target
    /// The night to judge it against. Nil means there's no night to offer —
    /// the sheet says to pick one rather than guessing.
    var night: NightPlan? = nil

    /// What happened to the last Add or View, when it couldn't go ahead.
    @State private var actionNote: String?

    private var result: TargetPlan? { night?.targets.first { $0.id == target.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.scaled(.title2, scale: uiTextScale).weight(.semibold))
                    Text("\(target.designation) · \(target.type.displayName) in \(target.constellationName)")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .padding(.bottom, 0)

            // As tall as this target needs when that fits, and scrolling
            // below the fixed title and Done when it doesn't: on a laptop
            // the full card was taller than the window, and a sheet that
            // overflows loses its top — title and Done included.
            ViewThatFits(in: .vertical) {
                details
                ScrollView { details }
            }
        }
        .frame(minWidth: 620, idealWidth: 760, maxWidth: 900)
        .frame(maxHeight: Self.maximumHeight)
        .spaceBackground()
    }

    /// The window the card opens over, less some room around it.
    private static var maximumHeight: CGFloat {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return max(360, (window?.contentLayoutRect.height ?? NSScreen.main?.visibleFrame.height ?? 800) - 40)
    }

    private var details: some View {
            VStack(alignment: .leading, spacing: 16) {
                // What this means for a real night comes first; the
                // reference material after it.
                nightSection

                // Two pictures, never three. Both survey images are the same
                // Digitized Sky Survey at different zooms, so the framed one
                // leads — it's what you'd actually get — and the close-up
                // crop only appears when there's no photograph to show what
                // the object itself looks like.
                HStack(alignment: .top, spacing: 12) {
                    labelledImage("Your frame · sky survey") {
                        FramingPreview(target: target, rig: state.rig)
                    }
                    if TargetImageCatalog.hasPhoto(for: target.designation) {
                        labelledImage("Photograph") {
                            TargetThumbnail(designation: target.designation, contentMode: .fit)
                        }
                    } else {
                        labelledImage("Close-up · sky survey") {
                            TargetSkyView(target: target)
                        }
                    }
                }
                .frame(height: 240)

                VStack(alignment: .leading, spacing: 8) {
                    factRow("Magnitude", String(format: "%.1f", target.magnitude))
                    factRow("Apparent size", target.sizeSummary)
                    factRow("Coordinates", Format.coordinates(target.coordinate))
                    if !target.type.isStarField {
                        factRow("Surface brightness", String(format: "%.1f mag/arcsec²", target.surfaceBrightness))
                    }
                }

                let curated = CuratedFacts.facts(for: target.designation)
                if !curated.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(curated, id: \.self) { fact in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•").foregroundStyle(Palette.accent)
                                Text(fact).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.scaled(.callout, scale: uiTextScale))
                }

                if let factInfo = TargetFactCatalog.info(for: target.designation) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(factInfo.fact)
                            .font(.scaled(.callout, scale: uiTextScale))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = URL(string: factInfo.sourceURL) {
                            Link(destination: url) {
                                Label("\(factInfo.sourceTitle) via Wikipedia", systemImage: "link")
                            }
                            .font(.scaled(.caption2, scale: uiTextScale))
                            .foregroundStyle(Palette.accent)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.panelBorder))
                }

                // Credit for the sky imagery, required by its licence.
                FramingCredit(rig: state.rig)

                if let info = TargetImageCatalog.info(for: target.designation),
                   let source = info.sourceURL, let url = URL(string: source) {
                    Link(destination: url) {
                        Label("Photo: \(info.sourceTitle ?? target.designation) via Wikipedia", systemImage: "link")
                    }
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.accent)
                }
            }
            .padding(24)
    }

    // MARK: - The night

    private func nightName(_ plan: NightPlan) -> String {
        "\(Format.weekday(plan.date, in: plan.timeZone)) \(Format.dayAndMonth(plan.date, in: plan.timeZone))"
    }

    private func times(_ window: TimeWindow, in plan: NightPlan) -> String {
        "\(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))"
    }

    @ViewBuilder
    private var nightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let night {
                SectionHeader("On \(nightName(night))")
                if let result {
                    HStack(alignment: .top, spacing: 12) {
                        ScoreBadge(score: result.score, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                VerdictTag(verdict: result.verdict)
                                Text([
                                    "\(result.usableHoursText) usable",
                                    result.bestWindow.map { "best window \(times($0, in: night))" }
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.scaled(.callout, scale: uiTextScale))
                                    .foregroundStyle(.secondary)
                            }
                            Text(targetVerdictSentence(result))
                                .font(.scaled(.callout, scale: uiTextScale).weight(.medium))
                            Text(result.fit.framingNote)
                                .font(.scaled(.callout, scale: uiTextScale))
                                .foregroundStyle(.secondary)
                            let planned = state.plannedBlocks(for: result.id, in: night)
                            if !planned.isEmpty {
                                Label("Planned · " + planned.map { times($0.window, in: night) }.joined(separator: ", "),
                                      systemImage: "checkmark.circle.fill")
                                    .font(.scaled(.callout, scale: uiTextScale))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            add(result, to: night)
                        } label: {
                            Label("Add to \(Format.weekday(night.date, in: night.timeZone))'s Plan", systemImage: "plus.circle.fill")
                                .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Opens the planner with this target added")
                        Button {
                            view(on: night)
                        } label: {
                            Label("View on \(Format.weekday(night.date, in: night.timeZone))", systemImage: "scope")
                                .font(.scaled(.body, scale: uiTextScale))
                        }
                        .help("Show this target in the main window")
                    }
                    .controlSize(.large)
                } else {
                    Label("No usable time on \(nightName(night)).",
                          systemImage: "moon.zzz")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let other = state.nearestUsefulNight(for: target.id, after: night) {
                        Text("Better on \(nightName(other.night)) · \(Int(other.target.score.rounded())) \(other.target.verdict.rawValue) · \(other.target.usableHoursText)")
                            .font(.scaled(.callout, scale: uiTextScale))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let actionNote {
                    Label(actionNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(Palette.marginal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SectionHeader("On a night")
                Text("Choose a night in the Night menu to see how this target does.")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.panelBorder))
    }

    private func add(_ result: TargetPlan, to night: NightPlan) {
        switch state.addFromCatalog(result, to: night) {
        case .added:
            dismiss()
            MainWindow.bringForward(using: openWindow)
        case .noRoom:
            actionNote = "\(nightName(night))'s plan is full. Shorten or remove a block, then add this again."
            MainWindow.bringForward(using: openWindow)
        case .plannerBusy(let other):
            actionNote = "The planner is open on \(Format.weekday(other, in: night.timeZone)) \(Format.dayAndMonth(other, in: night.timeZone)). Finish that plan first."
        }
    }

    private func view(on night: NightPlan) {
        if state.showFromCatalog(target.id, on: night) {
            dismiss()
            MainWindow.bringForward(using: openWindow)
        } else if let busy = state.nightBeingPlanned {
            actionNote = "The planner is open on \(nightName(busy)). Finish that plan first."
        }
    }

    private func labelledImage<Content: View>(_ title: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.spaceTop, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.panelBorder))
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.scaled(.callout, scale: uiTextScale))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
        }
    }
}

/// Add or edit a hand-typed target — anything the built-in catalog doesn't
/// cover. Coordinates are decimal degrees, matching how the site's own
/// latitude/longitude are entered in Settings, rather than introducing a
/// separate sexagesimal (HH:MM:SS) input style just for this form.
private struct CustomTargetEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    var existing: Target?

    @State private var designation: String
    @State private var commonName: String
    @State private var type: TargetType
    @State private var rightAscension: Double
    @State private var declination: Double
    @State private var magnitude: Double
    @State private var majorAxisArcminutes: Double
    @State private var minorAxisArcminutes: Double
    @State private var constellation: String

    init(existing: Target?) {
        self.existing = existing
        _designation = State(initialValue: existing?.designation ?? "")
        _commonName = State(initialValue: existing?.commonName ?? "")
        _type = State(initialValue: existing?.type ?? .emissionNebula)
        _rightAscension = State(initialValue: existing?.rightAscension ?? 0)
        _declination = State(initialValue: existing?.declination ?? 0)
        _magnitude = State(initialValue: existing?.magnitude ?? 8)
        _majorAxisArcminutes = State(initialValue: existing?.majorAxisArcminutes ?? 10)
        _minorAxisArcminutes = State(initialValue: existing?.minorAxisArcminutes ?? 10)
        _constellation = State(initialValue: existing?.constellation ?? "")
    }

    private var isValid: Bool {
        !designation.trimmingCharacters(in: .whitespaces).isEmpty
            && (0...360).contains(rightAscension)
            && (-90...90).contains(declination)
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Designation", text: $designation)
                TextField("Common name (optional)", text: $commonName)
                Picker("Type", selection: $type) {
                    ForEach(TargetType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Constellation (e.g. Cyg)", text: $constellation)
            }

            Section("Position (J2000, decimal degrees)") {
                TextField("Right ascension", value: $rightAscension, format: .number.precision(.fractionLength(4)))
                TextField("Declination", value: $declination, format: .number.precision(.fractionLength(4)))
            }

            Section("Size & Brightness") {
                TextField("Magnitude", value: $magnitude, format: .number.precision(.fractionLength(1)))
                HStack {
                    TextField("Major axis (′)", value: $majorAxisArcminutes, format: .number.precision(.fractionLength(1)))
                    TextField("Minor axis (′)", value: $minorAxisArcminutes, format: .number.precision(.fractionLength(1)))
                }
            }

            if existing != nil {
                Section {
                    Button("Delete Target", role: .destructive) {
                        if let existing { state.removeCustomTarget(existing) }
                        dismiss()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.spaceBackground)
        .frame(width: 420, height: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
    }

    private func save() {
        let trimmedCommonName = commonName.trimmingCharacters(in: .whitespaces)
        let target = Target(designation: designation.trimmingCharacters(in: .whitespaces),
                            commonName: trimmedCommonName.isEmpty ? nil : trimmedCommonName,
                            type: type,
                            rightAscension: rightAscension,
                            declination: declination,
                            magnitude: magnitude,
                            majorAxisArcminutes: majorAxisArcminutes,
                            minorAxisArcminutes: minorAxisArcminutes,
                            constellation: constellation.trimmingCharacters(in: .whitespaces))
        if let existing {
            state.updateCustomTarget(originalID: existing.id, with: target)
        } else {
            state.addCustomTarget(target)
        }
        dismiss()
    }
}

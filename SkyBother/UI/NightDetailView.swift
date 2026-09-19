import SwiftUI

struct NightDetailView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan

    /// Shared with the sky view — one clock between the two, not two
    /// independent ones. Starts at "now" when tonight is actually in
    /// progress, otherwise the middle of astronomical darkness, since that's
    /// the part of the night actually worth looking at.
    @State private var scrubTime: Date
    @State private var isSkyViewExpanded = false
    @State private var sortOption: TargetSortOption = .relevance
    @State private var isHeaderCollapsed = false
    /// Whether the plan strip is a drag surface rather than a picture.
    /// Transient on purpose — the *plan* is saved, but whether you currently
    /// have it open for editing is no more a preference than which target is
    /// selected.
    @State private var isEditingPlan = false
    /// True while the scroll view is actively moving — see the note on
    /// `NightTimelineView.isScrolling`; this is what actually drives it.
    @State private var isScrolling = false
    @State private var scrollSettleTask: Task<Void, Never>?

    /// Filtering happens in `AppState.visibleTargets(for:)`; sorting is a
    /// pure display concern on top of that, so it stays local view state
    /// rather than something the planner needs to know about.
    private var targets: [TargetPlan] {
        let filtered = state.visibleTargets(for: plan)
        switch sortOption {
        case .relevance:
            return filtered // already score-descending, straight from the planner
        case .alphabetical:
            return filtered.sorted { $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName) == .orderedAscending }
        case .size:
            return filtered.sorted { $0.target.majorAxisArcminutes > $1.target.majorAxisArcminutes }
        }
    }

    init(plan: NightPlan) {
        self.plan = plan
        // Sunset — the start of the chart window itself — every time,
        // tonight included, rather than jumping to the live clock whenever
        // tonight happens to already be underway: opening a night should
        // consistently land at the start of the session, not sometimes at
        // its beginning and sometimes wherever "now" happens to fall.
        _scrubTime = State(initialValue: plan.chartWindow.start)
    }

    /// Identifies the very top of the scroll content, so the compact header
    /// can scroll back to it on tap.
    private let topAnchorID = "nightDetailTop"

    /// The pane's own height on screen, republished down the tree for Sky
    /// View — see `EnvironmentValues.detailViewportHeight`.
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                Group {
                    if #available(macOS 15.0, *) {
                        plainScrollView
                            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                geometry.contentOffset.y
                            } action: { _, offset in
                                // The mission-summary card is roughly this
                                // tall; once it's scrolled past, swap in the
                                // compact score/best-target header in its place.
                                isHeaderCollapsed = offset > 130
                                markScrolling()
                            }
                    } else {
                        plainScrollView
                    }
                }

                if isHeaderCollapsed {
                    compactHeader
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation { proxy.scrollTo(topAnchorID, anchor: .top) }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isHeaderCollapsed)
        // Measured on the pane itself rather than on the scrolled content:
        // this is the size of the window's hole, which is what a square view
        // inside an unbounded scrolling column has no other way to learn.
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { viewportHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
            }
        )
        .environment(\.detailViewportHeight, viewportHeight)
        // The hero card below already owns the selected night's identity
        // (date, verdict, best target) in a much bigger typeface — repeating
        // the date here just gave the same fact two competing headings. The
        // title bar is for the thing the hero doesn't say: where you're
        // observing from.
        .navigationTitle(plan.site.name)
    }

    /// Marks scrolling as in-flight and schedules clearing it again after a
    /// short quiet period — `onScrollGeometryChange` only fires while the
    /// offset is actually changing, not on a distinct "scroll ended" event,
    /// so this is a simple debounce rather than a real gesture-end signal.
    private func markScrolling() {
        isScrolling = true
        scrollSettleTask?.cancel()
        scrollSettleTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            isScrolling = false
        }
    }

    /// Retains just the score, date/verdict and best target once the full
    /// mission-summary card above has scrolled out of view — the same
    /// glanceable identity the card gives you, without scrolling back up.
    private var compactHeader: some View {
        HStack(spacing: 9) {
            ScoreBadge(score: plan.score, size: 26)
            Text(Format.longDate(plan.date, in: plan.timeZone))
                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                .lineLimit(1)
            Text("·").foregroundStyle(.tertiary)
            Text(plan.verdict.rawValue)
                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                .foregroundStyle(Palette.verdict(plan.verdict))
            if let best = plan.bestTarget {
                Text("·").foregroundStyle(.tertiary)
                Text("Best: \(best.target.displayName) · \(Int(best.score.rounded()))")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Palette.spaceTop, in: Rectangle())
        .overlay(Divider(), alignment: .bottom)
    }

    // One scroll view for the whole column — mission summary, stats,
    // timeline, legend and tonight's plan at the top, then the target
    // list below — rather than two independently-scrolling regions
    // stacked on top of each other. The filter bar pins in place as a
    // section header once you scroll past it, so it stays reachable
    // while browsing targets without needing its own scroll area.
    private var plainScrollView: some View {
        ScrollView {
            // The header (mission summary, stats, timeline, legend, tonight's
            // plan) is one big one-off block, not repeating content — it
            // stays in a plain VStack, laid out eagerly like normal, rather
            // than as a sibling item inside the LazyVStack below. Lazy
            // stacks estimate the size of anything not yet on screen, and a
            // block this tall and this variable (a whole chart, a
            // conditional cloud-out banner) is exactly the kind of item that
            // estimate gets wrong — which showed up as the scroll position
            // visibly fighting itself while scrolling back up past it. The
            // target list below, which can run to 60+ rows, is the part that
            // actually benefits from being lazy.
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(20)
                    .id(topAnchorID)
                Divider()
            }

            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    targetListContent
                } header: {
                    filterBar
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Palette.panel)
                    Divider()
                }
            }
        }
        .scrollIndicators(.visible)
        .spaceBackground()
    }

    // MARK: - Header

    private var selectedTargetPlan: TargetPlan? {
        guard let id = state.selectedTargetID else { return nil }
        return plan.targets.first { $0.id == id }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            missionSummary

            statistics

            // No .animation() here deliberately: NightTimelineView draws
            // everything in a Canvas, which redraws immediately rather than
            // interpolating, so this had no visible effect on the selection
            // change it looked like it was meant to smooth. What it did do
            // is sweep in the timeline's own unrelated internal state (hover
            // tracking, which refires while the content scrolls under a
            // stationary cursor) into an animated transaction — fighting the
            // scroll view's own momentum and producing a visible jitter that
            // made it hard to scroll back to the top.
            NightTimelineView(plan: plan, selectedTarget: selectedTargetPlan, scrubTime: $scrubTime, isScrolling: isScrolling)

            legend

            skySection

            autoPlanSection
        }
    }

    // MARK: - Sky view

    /// Collapsed by default — this is a new, optional lens on the same
    /// night, not a replacement for the density Phase 1B already tuned for
    /// people who just want the deep-sky planner.
    private var skySection: some View {
        DisclosureGroup(isExpanded: $isSkyViewExpanded) {
            SkyView(plan: plan, scrubTime: $scrubTime, autoPlanSlots: autoPlan)
                .padding(.top, 12)
        } label: {
            SectionHeader("Sky view")
                // DisclosureGroup only toggles on its own triangle by
                // default — the label itself isn't otherwise clickable.
                .contentShape(Rectangle())
                .onTapGesture { isSkyViewExpanded.toggle() }
        }
        .tint(Palette.accent)
    }

    // MARK: - Auto-plan

    private var autoPlan: [AutoPlanSlot] {
        // Nothing to suggest for a night that's clouded out. `Planner` keeps a
        // target list for such a night on purpose — re-planned ignoring cloud,
        // so the list can say "this is what you'd have had" rather than look
        // broken — but a running order built out of those is a schedule for a
        // night that isn't happening, and reads as though the app hasn't
        // noticed the forecast.
        guard !plan.isCloudedOut else { return [] }
        return AutoPlanner.plan(for: plan, minimumScore: state.preferences.minimumScore,
                                sessionCapMinutes: sessionCapMinutes)
    }

    /// What the strip actually shows: your own plan once you have one, and the
    /// app's suggestion until then. `nil` from the store is meaningfully
    /// different from an empty array — the first means "still following the
    /// suggestion", the second means "I cleared this night on purpose" — which
    /// is why a cleared night doesn't quietly fill itself back in.
    private var planSegments: [PlanSegment] {
        state.storedPlan(for: plan) ?? autoPlan.map {
            PlanSegment(targetID: $0.targetPlan.id,
                        targetName: $0.targetPlan.target.displayName,
                        window: $0.window)
        }
    }

    private var isOwnPlan: Bool { state.storedPlan(for: plan) != nil }

    /// Minutes in the plan that its targets can't actually be shot in — the
    /// one number worth putting in the header, since a hand-built plan is
    /// allowed to contain them and you'd otherwise have to spot the hatching.
    private var unshootableMinutes: Double {
        planSegments.reduce(0) { total, segment in
            total + segment.unusableMinutes(against: plan.targets.first { $0.id == segment.targetID })
        }
    }

    /// See `Preferences.sessionCapMinutes` — the Integration Goal, or half of
    /// it when the plan is asked to favour more targets over longer ones.
    private var sessionCapMinutes: Double { state.preferences.sessionCapMinutes }

    private var autoPlanSection: some View {
        let segments = planSegments.chronological
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SectionHeader("Tonight's plan")
                planOriginBadge
                Spacer()
                if !segments.isEmpty {
                    Text(planSummary(segments))
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(unshootableMinutes > 0 ? Palette.marginal : .secondary)
                }
                if isEditingPlan {
                    if !segments.isEmpty {
                        planButton("Clear") { state.clearPlan(for: plan) }
                    }
                    if isOwnPlan {
                        planButton("Reset") { state.revertPlanToSuggested(for: plan) }
                    }
                }
                planButton(isEditingPlan ? "Done" : "Edit plan",
                           systemImage: isEditingPlan ? "checkmark.circle.fill" : "slider.horizontal.below.rectangle") {
                    if !isEditingPlan { state.beginEditingPlan(for: plan, seededWith: autoPlan) }
                    isEditingPlan.toggle()
                }
            }

            if segments.isEmpty {
                Text(emptyPlanMessage)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            } else {
                PlanStripView(plan: plan, segments: segments, isEditing: isEditingPlan) { edited in
                    state.setPlan(edited, for: plan)
                }
                // One height in both modes. Growing on entering edit mode
                // shoved everything below it down the page at the exact moment
                // you were reaching for a block, so the thing you were aiming
                // at moved. Edit mode announces itself by its outline instead.
                .frame(height: 38)

                if isEditingPlan {
                    Text("Drag a block to move it, or either end to change how long you spend there. The same target can take as many blocks of the night as you like. Hatched means the target isn't up, dark or clear then — allowed, just flagged.")
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        planRow(segment)
                        if index < segments.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .panelStyle()
            }
        }
    }

    /// Says in one word whose plan this is. Without it the two are visually
    /// identical, and the difference decides what the buttons beside it do —
    /// Reset throws away work on a manual plan and does nothing at all to a
    /// suggested one.
    private var planOriginBadge: some View {
        let manual = isOwnPlan
        return Text(manual ? "Manual" : "Suggested")
            .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
            .foregroundStyle(manual ? Palette.accent : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(manual ? Palette.accent.opacity(0.16) : Color.primary.opacity(0.07))
            )
            .overlay(
                Capsule().strokeBorder(manual ? Palette.accent.opacity(0.45) : Color.clear)
            )
            .help(manual
                  ? "You have edited this night. It stays exactly as you left it — the app won't re-plan it."
                  : "The app's own suggestion. Editing it, or pressing Edit plan, makes it yours.")
    }

    private var emptyPlanMessage: String {
        if plan.isCloudedOut {
            return "Clouded out — nothing to plan. The target list below shows what would have been up if it clears."
        }
        if isEditingPlan {
            return "Nothing planned. Press + beside any target below to drop it into the night, then drag it where you want it."
        }
        return "Nothing tonight clears your minimum score for long enough to build a session around."
    }

    private func planSummary(_ segments: [PlanSegment]) -> String {
        let blocks = "\(segments.count) block\(segments.count == 1 ? "" : "s")"
        let hours = Format.hours(segments.totalMinutes / 60)
        guard unshootableMinutes > 0 else { return "\(blocks) · \(hours)" }
        return "\(blocks) · \(hours) · \(Format.duration(minutes: unshootableMinutes)) unshootable"
    }

    private func planButton(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
        .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
    }

    private func planRow(_ segment: PlanSegment) -> some View {
        let targetPlan = plan.targets.first { $0.id == segment.targetID }
        let unshootable = segment.unusableMinutes(against: targetPlan)
        let isSelected = state.selectedTargetID == segment.targetID
        return HStack(spacing: 12) {
            ScoreBadge(score: targetPlan?.score ?? 0, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.targetName)
                    .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                Group {
                    if targetPlan == nil {
                        Text("Not up, dark or clear at all tonight")
                    } else if unshootable > 0 {
                        Text("\(Format.duration(minutes: unshootable)) of this block is unshootable")
                    } else {
                        Text(targetPlan?.fit.framingNote ?? "")
                    }
                }
                .font(.scaled(.caption, scale: uiTextScale))
                .foregroundStyle(unshootable > 0 || targetPlan == nil ? Palette.marginal : .secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.time(segment.window.start, in: plan.timeZone))–\(Format.time(segment.window.end, in: plan.timeZone))")
                    .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(Format.duration(minutes: segment.window.durationMinutes))
                    .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isEditingPlan {
                Button {
                    state.removePlanSegment(id: segment.id, from: plan)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this block from the plan")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Palette.accent.opacity(0.18) : Color.clear)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture { state.selectedTargetID = segment.targetID }
    }

    // MARK: - Mission summary

    /// The 2-3-second answer: is tonight worth it, when, at what, and why
    /// not more. Everything below this is the detail that backs it up.
    private var missionSummary: some View {
        HStack(alignment: .center, spacing: 16) {
            ScoreBadge(score: plan.score, size: 58)
            // Three distinct lines rather than one run-on sentence: the
            // operational fact (when to shoot), the recommendation (what to
            // shoot), and the caveat (what's limiting it) each read as their
            // own thought instead of being flattened into equally-weighted
            // clauses of a single caption.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(Format.longDate(plan.date, in: plan.timeZone))
                        .font(.scaled(.title2, scale: uiTextScale).weight(.bold))
                    VerdictTag(verdict: plan.verdict)
                }
                // Capped at 2 lines with that height always reserved, rather
                // than `.fixedSize(vertical: true)`'s unbounded growth — this
                // line falls back to `plan.headline` (a full sentence) on a
                // night with no best-imaging window, which is often long
                // enough to wrap where the short "Best imaging HH:MM–HH:MM"
                // line on a good night doesn't. Switching between the two
                // was pushing the timeline and everything below it down;
                // reserving the space up front keeps the card the same
                // height regardless of which night is selected.
                Text(operationalSummaryLine)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .hoverTooltip(operationalSummaryLine)
                if let best = plan.bestTarget {
                    let bestTargetLine = "\(best.target.displayName) · \(Int(best.score.rounded()))"
                    HStack(spacing: 6) {
                        Text("Best target")
                            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        Text(bestTargetLine)
                            .font(.scaled(.callout, scale: uiTextScale).weight(.medium))
                            .lineLimit(1)
                    }
                    .hoverTooltip(bestTargetLine)
                }
                if let limitation = nightLimitationPhrase(for: plan) {
                    let limitationLine = "Main limitation: \(limitation)"
                    Text(limitationLine)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .hoverTooltip(limitationLine)
                }
            }
            Spacer(minLength: 0)
            // A compact badge rather than the full-width banner this used to
            // be: that banner sat between the header and the timeline, so on
            // every clouded-out night it inserted or removed a whole block
            // and shoved the timeline, legend and Tonight's Plan down —
            // visually noisy on exactly the nights this fires most. Living
            // here instead, it's just one more fixed-size item in a row that
            // already reflows around variable content, so nothing below the
            // card moves.
            if plan.isCloudedOut {
                VStack(spacing: 2) {
                    Image(systemName: "cloud.rain.fill")
                        .font(.scaled(.title, scale: uiTextScale))
                        .foregroundStyle(Palette.marginal)
                    Text("Clouded Out")
                        .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                        .foregroundStyle(Palette.marginal)
                }
                .hoverTooltip("The forecast writes this night off. The list below shows what would have been up if it clears.")
            }
            MoonPhaseDisc(illuminatedFraction: plan.moon.illuminatedFraction, isWaxing: plan.moon.isWaxing, diameter: 34)
                .hoverTooltip("\(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())")
        }
        .padding(16)
        .panelStyle(cornerRadius: 14)
        .animation(.easeInOut(duration: 0.3), value: plan.id)
    }

    private var operationalSummaryLine: String {
        if let window = plan.bestImagingWindow, !window.isEmpty {
            return "Best imaging \(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))"
        }
        return plan.headline
    }

    private var statistics: some View {
        HStack(alignment: .top, spacing: 26) {
            LabelledValue(label: "Astronomical dark",
                          value: darkWindowText,
                          systemImage: "moon.stars")
            LabelledValue(label: "Moon down",
                          value: plan.moonlessDarkHours > 0.02 ? Format.hours(plan.moonlessDarkHours) : "none",
                          systemImage: plan.moon.symbolName)
            LabelledValue(label: "Moon",
                          value: "\(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())",
                          systemImage: "circle.lefthalf.filled")
            if plan.hasWeather {
                LabelledValue(label: "Cloud in the dark",
                              value: "\(Int(plan.meanCloudDuringDark))%",
                              systemImage: "cloud")
                LabelledValue(label: "Low",
                              value: Format.temperature(celsius: plan.minimumTemperature,
                                                        imperial: state.preferences.usesImperialUnits),
                              systemImage: "thermometer.low")
                LabelledValue(label: "Dew spread",
                              value: Format.temperatureDelta(celsius: plan.minimumDewSpread,
                                                             imperial: state.preferences.usesImperialUnits),
                              systemImage: "humidity")
                LabelledValue(label: "Gusts",
                              value: Format.wind(kilometersPerHour: plan.maximumGust,
                                                 imperial: state.preferences.usesImperialUnits),
                              systemImage: "wind")
            }
            Spacer(minLength: 0)
        }
    }

    private var darkWindowText: String {
        guard let dusk = plan.astronomicalDusk, let dawn = plan.astronomicalDawn else {
            return plan.darkWindows.isEmpty ? "none" : Format.hours(plan.darkHours)
        }
        return "\(Format.time(dusk, in: plan.timeZone))–\(Format.time(dawn, in: plan.timeZone))"
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: Palette.cloud.opacity(0.7), label: "cloud from the top")
            legendItem(color: Palette.moonlight.opacity(0.8), label: "moonlight and its altitude")
            legendItem(color: Palette.astronomical, label: "darker background = darker sky")
            if let target = selectedTargetPlan {
                legendItem(color: Palette.accent, label: "\(target.target.displayName)'s altitude · shaded box = its best window")
            }
            Spacer()
            if let dewWarning = dewWarning {
                Label(dewWarning, systemImage: "drop.fill")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.marginal)
            }
        }
        .font(.scaled(.caption, scale: uiTextScale))
        .foregroundStyle(.secondary)
    }

    private var dewWarning: String? {
        guard plan.hasDewRisk else { return nil }
        return "Dew likely — bring a dew heater"
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 14, height: 9)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.15)))
            // Fixed to one line: the selected-target item's label is dynamic
            // (target name included) and, unconstrained, would wrap to a
            // second line in a narrower window — growing the whole legend
            // row's height every time a selection appears or disappears,
            // shifting everything below it. Truncating keeps the row's
            // height constant regardless of what's selected.
            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .hoverTooltip(label)
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter targets", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 190)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.panelBorder))

            Menu {
                Button("All Types") { state.typeFilter.removeAll() }
                Divider()
                ForEach(TargetType.allCases) { type in
                    Toggle(type.displayName, isOn: Binding(
                        get: { state.typeFilter.contains(type) },
                        set: { isOn in
                            if isOn { state.typeFilter.insert(type) } else { state.typeFilter.remove(type) }
                        }))
                }
            } label: {
                Label(state.typeFilter.isEmpty ? "All Types" : "\(state.typeFilter.count) Types",
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(TargetSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if state.isPlanning {
                ProgressView().controlSize(.small)
            }
            // One line only: unconstrained, a narrow center column squeezes
            // this down to a single character per line and the whole bar
            // grows hundreds of points tall. Short form when the long one
            // doesn't fit.
            ViewThatFits(in: .horizontal) {
                Text("\(targets.count) targets meet criteria")
                Text("\(targets.count) targets")
            }
            .lineLimit(1)
            .font(.scaled(.callout, scale: uiTextScale))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Targets

    @ViewBuilder
    private var targetListContent: some View {
        if targets.isEmpty {
            EmptyStateView(title: emptyTitle,
                           message: emptyMessage,
                           systemImage: "binoculars")
                .frame(minHeight: 320)
        } else {
            ForEach(targets) { targetPlan in
                HStack(spacing: 10) {
                    if isEditingPlan {
                        // Add, not check: a target can be in the plan more
                        // than once, so there is no on/off state for this
                        // button to show. Pressing it twice is a legitimate
                        // thing to do and gives you two blocks.
                        Button {
                            state.addPlanSegment(for: targetPlan, to: plan)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.scaled(.title3, scale: uiTextScale))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .help("Add a block for this target at the longest gap left in the night")
                    }
                    TargetRowView(plan: plan, targetPlan: targetPlan,
                                 isSelected: state.selectedTargetID == targetPlan.id)
                }
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .onTapGesture { state.selectedTargetID = targetPlan.id }
                Divider().padding(.leading, 20)
            }
        }
    }

    private var emptyTitle: String {
        plan.darkWindows.isEmpty ? "No darkness tonight" : "Nothing clears your thresholds"
    }

    private var emptyMessage: String {
        if plan.darkWindows.isEmpty {
            return "The sun never gets far enough below the horizon at this latitude and date."
        }
        if !state.searchText.isEmpty || !state.typeFilter.isEmpty {
            return "No targets match the current filter."
        }
        return "Try lowering the minimum altitude or minimum score in Settings."
    }
}

enum TargetSortOption: String, CaseIterable, Identifiable {
    case relevance = "Most Relevant"
    case alphabetical = "Alphabetical"
    case size = "Size in the Sky"

    var id: String { rawValue }
}

struct TargetRowView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var targetPlan: TargetPlan
    var isSelected: Bool = false

    /// Tapping the thumbnail opens the same reference-catalog card the
    /// Target Catalog window uses (photo, facts, discovery trivia when
    /// there is any) — a quick look at what you're actually pointing at,
    /// without leaving tonight's plan. The rest of the row keeps its own
    /// tap behaviour (selecting it in the inspector on the right).
    @State private var isShowingCatalogDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ScoreBadge(score: targetPlan.score, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(targetPlan.target.displayName)
                        .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                    if targetPlan.target.commonName != nil {
                        Text(targetPlan.target.designation)
                            .font(.scaled(.callout, scale: uiTextScale))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: targetPlan.target.type.symbolName)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(Palette.accent)
                    Text(targetPlan.target.type.shortName)
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }

                TargetAvailabilityBar(plan: plan, targetPlan: targetPlan)

                HStack(spacing: 5) {
                    Text(summary)
                        .font(.scaled(.callout, scale: uiTextScale).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let risk = targetPlan.bestWindowZenithRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.scaled(.caption, scale: uiTextScale))
                            .foregroundStyle(Palette.marginal)
                            .hoverTooltip("Zenith risk from \(Format.time(risk.start, in: plan.timeZone)) — field rotation peaks near the zenith and some alt-az mounts stall there.")
                    }
                }
            }

            TargetThumbnail(designation: targetPlan.target.designation)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.panelBorder))
                .contentShape(Rectangle())
                .onTapGesture { isShowingCatalogDetail = true }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Palette.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .sheet(isPresented: $isShowingCatalogDetail) {
            TargetCatalogDetail(target: targetPlan.target)
        }
    }

    /// Fixed-order, fixed-format fields rather than prose — so scanning
    /// straight down the list compares the same value in the same place on
    /// every row instead of parsing a different sentence shape each time.
    private var summary: String {
        var parts: [String] = []
        if let best = targetPlan.bestTime {
            parts.append("\(Format.time(best, in: plan.timeZone)) best")
        }
        parts.append("\(Format.degrees(targetPlan.maximumAltitude)) peak")
        parts.append("\(Int((targetPlan.fit.fillFraction * 100).rounded()))% frame")
        parts.append(targetPlan.usableHoursText)
        return parts.joined(separator: " · ")
    }
}

/// A Gantt-style strip of the auto-planned session, sharing the night
/// timeline's time axis so it lines up with everything above it.
private struct AutoPlanStripView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.uiTextScale) private var uiTextScale
    var plan: NightPlan
    var slots: [AutoPlanSlot]

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)
            Canvas { context, size in
                // A dark track first, so the gap between segments below reads
                // clearly no matter what sits behind this view.
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                             with: .color(Palette.spaceTop))

                // Two consecutive targets often land within a point or two of
                // each other on the score-color scale, so a shared edge alone
                // can vanish entirely. A real gap reads as a boundary no
                // matter how close the colours are, which a same-colour
                // stroke never reliably does.
                let gap: CGFloat = 3
                for slot in slots {
                    let startX = axis.x(for: slot.window.start)
                    let endX = axis.x(for: slot.window.end)
                    let rect = CGRect(x: startX + gap / 2, y: 0,
                                      width: max(2, (endX - startX) - gap), height: size.height)
                    let color = Palette.score(slot.targetPlan.score)
                    let isSelected = state.selectedTargetID == slot.targetPlan.id
                    // Selection outline uses the app's one accent colour
                    // rather than plain white, so this strip agrees with the
                    // sidebar, target list and timeline about what
                    // "selected" looks like instead of inventing its own.
                    context.fill(Path(roundedRect: rect, cornerRadius: 5),
                                 with: .color(color.opacity(isSelected ? 0.95 : 0.75)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 5),
                                   with: .color(isSelected ? Palette.accent : color), lineWidth: isSelected ? 2 : 1)

                    if rect.width > 50 {
                        context.draw(Text(slot.targetPlan.target.displayName)
                                        .font(.system(size: 11 * uiTextScale, weight: .semibold))
                                        .foregroundColor(.white),
                                     at: CGPoint(x: rect.midX, y: rect.midY),
                                     anchor: .center)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        let x = value.location.x
                        if let hit = slots.first(where: { x >= axis.x(for: $0.window.start) && x <= axis.x(for: $0.window.end) }) {
                            state.selectedTargetID = hit.targetPlan.id
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.panelBorder))
    }
}

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
    @State private var isHeaderCollapsed = false
    /// The easter egg: the header's moon opens tonight's Moon, properly drawn.
    @State private var isShowingMoon = false
    /// True while the scroll view is actively moving — see the note on
    /// `NightTimelineView.isScrolling`; this is what actually drives it.
    @State private var isScrolling = false
    @State private var scrollSettleTask: Task<Void, Never>?
    /// The pane's height and the header's, for deciding how many other
    /// targets fit underneath without scrolling.
    @State private var viewportHeight: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    /// The wide layout's left column above the big dome.
    @State private var leftColumnHeight: CGFloat = 0
    /// A highlight on the big dome, clicked: its catalog card.
    @State private var catalogTarget: Target?
    /// A real other-targets row, once one has been laid out.
    @State private var measuredRowHeight: CGFloat = 0

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
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        viewportHeight = geometry.size.height
                        viewportWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size) { _, size in
                        viewportHeight = size.height
                        viewportWidth = size.width
                    }
            }
        )
        // The hero card below already owns the selected night's identity
        // (date, verdict, best target) in a much bigger typeface — repeating
        // the date here just gave the same fact two competing headings. The
        // title bar is for the thing the hero doesn't say: where you're
        // observing from.
        .navigationTitle(plan.site.name)
        // On a big screen the target panel is a whole column; rather than
        // open on "No target selected", it shows the night's best.
        .onChange(of: isWide, initial: true) { _, wide in
            if wide, state.selectedTargetID == nil, let best = plan.bestTarget {
                state.selectedTargetID = best.id
            }
        }
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

    // One scroll view for the whole column: summary, conditions, timeline,
    // Sky View and the plan. Browsing every target lives in the planner now,
    // so this column answers "is this night worth it" and nothing more.
    private var plainScrollView: some View {
        ScrollView {
            if isWide {
                wideLayout
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(20)
                        .id(topAnchorID)
                        .background(heightReader)
                    otherTargetsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .scrollIndicators(.visible)
        .spaceBackground()
        .background(alignment: .top) { fitProbes }
    }

    /// Measures whatever sits above the other targets, for `otherTargetCount`.
    private var heightReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { headerHeight = geometry.size.height }
                .onChange(of: geometry.size.height) { _, height in headerHeight = height }
        }
    }

    // MARK: - Wide layout

    /// A big display gives this column two thousand points or more. Stacked
    /// in one column, everything just stretched across it: the timeline got
    /// long and thin and each plan row put its name and its times a screen
    /// apart. Past this width (in points at 100%, so it tracks the UI scale)
    /// the plan and the other targets move into a column of their own beside
    /// the summary, conditions and timeline. A laptop never gets here; a
    /// 27" 1440p and up does. The left column keeps at least the width this
    /// whole column has on a full-screen laptop (about 530 at 100%), beside
    /// a 520 plan column.
    private static let wideLayoutMinWidth: CGFloat = 1120

    private var isWide: Bool {
        viewportWidth / uiTextScale >= Self.wideLayoutMinWidth
    }

    /// The plan column: wide enough for a plan row's name and times to sit
    /// comfortably apart, and no wider.
    private var sideColumnWidth: CGFloat {
        min(max(viewportWidth * 0.4, 520 * uiTextScale), 700 * uiTextScale)
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                missionSummary
                statistics
                // Taller with the UI scale here: at a fixed height, this
                // column's width left the chart a thin ribbon.
                timelineWithDew(height: 200 * uiTextScale)
                legend
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { leftColumnHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in leftColumnHeight = height }
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) { bigDome }

            VStack(alignment: .leading, spacing: 24) {
                autoPlanSection
                    .background(heightReader)
                otherTargetsSection
            }
            .frame(width: sideColumnWidth, alignment: .leading)
        }
        .padding(20)
        .id(topAnchorID)
    }

    /// The height left under the wide layout's left column: the window's
    /// height less the column and the padding round it. It was empty — half
    /// a 4K window of nothing under the chart.
    private var bigDomeHeight: CGFloat {
        viewportHeight - leftColumnHeight - 40 - 24
    }

    /// The sky, big, in the space under the chart: tonight's as it is now,
    /// kept current, any other night's at its best stretch. Click for Sky View.
    private var showsBigDome: Bool { isWide && bigDomeHeight > 260 }

    /// What the big dome points out, best first: the plan's targets, then
    /// the named showpieces, then the rest of the Messier list, each by
    /// brightness. Not just tonight's — a showpiece that's only up by day
    /// still gets marked, and its card says when to catch it. The dome keeps
    /// as many as fit without overlapping.
    private var domeHighlights: [Target] {
        let catalog = BuiltInCatalog.all + state.customTargets
        let planned = planSegments.chronological.compactMap { segment in
            catalog.first { $0.id == segment.targetID }
        }
        let famous = (BuiltInCatalog.messier + BuiltInCatalog.showpieces).sorted {
            let a = $0.commonName != nil, b = $1.commonName != nil
            return a != b ? a : $0.magnitude < $1.magnitude
        }
        var seen = Set<String>()
        return (planned + famous).filter { seen.insert($0.id).inserted }
    }

    @ViewBuilder
    private var bigDome: some View {
        let height = bigDomeHeight
        if showsBigDome {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let time = isTonight ? context.date : skyPreviewTime
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionHeader(isTonight ? "In the sky now · \(Format.time(time, in: plan.timeZone))"
                                                : "In the sky · \(Format.time(time, in: plan.timeZone))")
                        Spacer()
                        Button {
                            state.openSkyView(for: plan)
                        } label: {
                            Label("Open Sky View", systemImage: "circle.dashed.inset.filled")
                                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                    }
                    // Clicking a marked target opens its card; anywhere else
                    // on the sky opens Sky View.
                    SkyView(plan: plan, scrubTime: .constant(time), isPlaying: .constant(false),
                            planSegments: planSegments, showsControls: false, showsLabels: true,
                            highlights: domeHighlights,
                            onSelectHighlight: { catalogTarget = $0 })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { state.openSkyView(for: plan) }
                }
                .padding(14)
                .panelStyle(cornerRadius: 14)
            }
            .frame(height: height)
            .offset(y: leftColumnHeight + 24)
            .sheet(item: $catalogTarget) { target in
                TargetCatalogDetail(target: target, night: plan)
            }
        }
    }

    // MARK: - Other targets

    /// Measured once a row exists: padding that doesn't scale makes a row
    /// taller than the estimate at small scales, and the last one got cut off.
    private var otherRowHeight: CGFloat {
        measuredRowHeight > 0 ? measuredRowHeight + 1 : 84 * uiTextScale
    }

    /// How many rows fit below the header without scrolling — below the
    /// plan, in the wide layout. Zero unless at least three do: on a smaller
    /// window Home stays as it was.
    private var otherTargetCount: Int {
        guard viewportHeight > 0, headerHeight > 0 else { return 0 }
        let chrome = (isWide ? 110 : 90) * uiTextScale   // section title and the planner link
        let rows = Int((viewportHeight - headerHeight - chrome) / otherRowHeight)
        return rows >= 3 ? min(rows, isWide ? 12 : 8) : 0
    }

    /// The night's best targets that aren't already in the plan. Read
    /// straight from the planner's results rather than the planner's own
    /// list, which carries whatever search and filters were last used there.
    private var otherTargets: [TargetPlan] {
        let planned = Set(planSegments.map(\.targetID))
        return plan.targets
            .filter { $0.usableMinutes > 0 && $0.score >= state.preferences.minimumScore && !planned.contains($0.id) }
            .sorted { $0.score > $1.score }
    }

    @ViewBuilder
    private var otherTargetsSection: some View {
        let count = otherTargetCount
        let targets = Array(otherTargets.prefix(count))
        if count > 0 && !targets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(plan.isCloudedOut ? "If it clears" : "Other targets of interest")
                VStack(spacing: 0) {
                    ForEach(targets) { targetPlan in
                        TargetRowView(plan: plan, targetPlan: targetPlan,
                                      isSelected: state.selectedTargetID == targetPlan.id)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .onAppear { measuredRowHeight = geometry.size.height }
                                        .onChange(of: geometry.size.height) { _, height in measuredRowHeight = height }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { state.selectedTargetID = targetPlan.id }
                        if targetPlan.id != targets.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .panelStyle()
                Button {
                    state.openPlanner(for: plan)
                } label: {
                    Label("See All in the Planner", systemImage: "list.bullet.rectangle")
                        .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
            }
        }
    }

    // MARK: - Fitting the UI scale

    /// Hidden copies of the rows in this column that must stay on one line,
    /// laid out at the same width as the real ones, for the automatic UI
    /// scale to measure.
    private var fitProbes: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(planSegments.chronological) { segment in
                planRow(segment).reportsOneLineFit()
            }
        }
        .padding(20)
        // In the wide layout the plan rows are in the right-hand column.
        .frame(width: isWide ? sideColumnWidth + 40 : nil)
        .frame(maxWidth: .infinity, alignment: .trailing)
        // Content width, not the scroll view's: always-visible scroll bars
        // take their width out of what the rows get.
        .padding(.trailing, NSScroller.preferredScrollerStyle == .legacy
                 ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            timelineWithDew()

            legend

            autoPlanSection
        }
    }

    private func timelineWithDew(height: CGFloat = 152) -> some View {
        VStack(spacing: 5) {
            NightTimelineView(plan: plan, height: height, selectedTarget: selectedTargetPlan,
                              scrubTime: $scrubTime, isScrolling: isScrolling)
            if plan.hasWeather {
                DewRiskStrip(plan: plan, imperial: state.preferences.usesImperialUnits, isScrolling: isScrolling)
            }
        }
    }

    // MARK: - Sky view

    /// Sky View is the most striking thing in the app, so the summary shows
    /// it rather than naming it: this night's own sky, drawn small, in the
    /// middle of the best imaging window. The picture is the button.
    private var skyDomeButton: some View {
        Button {
            state.openSkyView(for: plan)
        } label: {
            VStack(spacing: 6) {
                // Tonight's is the sky right now, kept current; any other
                // night's, its best stretch.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    SkyView(plan: plan, scrubTime: .constant(isTonight ? context.date : skyPreviewTime),
                            isPlaying: .constant(false), planSegments: planSegments, showsControls: false)
                }
                    .frame(width: 104 * uiTextScale, height: 104 * uiTextScale)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Label("Open Sky View", systemImage: "circle.dashed.inset.filled")
                    .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Sky View")
        .accessibilityLabel("Open Sky View for \(Format.longDate(plan.date, in: plan.timeZone))")
    }

    /// Same test as the sidebar's "Tonight" label.
    private var isTonight: Bool { plan.id == state.plans.first?.id }

    /// When the preview is drawn: the middle of the best imaging window, when
    /// the sky is properly dark, or failing that the middle of the night.
    private var skyPreviewTime: Date {
        plan.bestImagingWindow?.midpoint ?? plan.chartWindow.midpoint
    }

    // MARK: - Plan summary

    /// Your own plan once you have one, and the app's suggestion until then.
    /// Home only ever reads it; changing it happens in the planner.
    private var planSegments: [PlanSegment] { state.displayedPlan(for: plan) }

    private var isOwnPlan: Bool { state.isManualPlan(for: plan) }

    /// Minutes in the plan that its targets can't actually be shot in — the
    /// one number worth putting in the header, since a hand-built plan is
    /// allowed to contain them and you'd otherwise have to spot the hatching.
    private var unshootableMinutes: Double {
        planSegments.reduce(0) { total, segment in
            total + segment.unusableMinutes(against: plan.targets.first { $0.id == segment.targetID })
        }
    }

    private var autoPlanSection: some View {
        let segments = planSegments.chronological
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Same test as the sidebar's "Tonight" label.
                SectionHeader(plan.id == state.plans.first?.id
                              ? "Tonight's plan"
                              : "\(Format.fullWeekday(plan.date, in: plan.timeZone))'s plan")
                planOriginBadge
                Spacer()
                if !segments.isEmpty {
                    Text(planSummary(segments))
                        .font(.scaled(.caption, scale: uiTextScale))
                        .foregroundStyle(unshootableMinutes > 0 ? Palette.marginal : .secondary)
                }
                planButton("Edit Plan", systemImage: "slider.horizontal.below.rectangle") {
                    state.openPlanner(for: plan)
                }
                .help("Open the planner to change this night's plan")
            }

            if segments.isEmpty {
                Text(emptyPlanMessage)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
            } else if segments.count == 1 {
                // One target needs no Gantt strip: a single full-width bar
                // says nothing the row's own times don't.
                planRow(segments[0])
                    .panelStyle()
            } else {
                PlanStripView(plan: plan, segments: segments, isEditing: false)
                    .frame(height: 38)

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

    /// The glanceable at-the-scope view of tonight's plan.
    private var sessionButton: some View {
        ViewSessionButton(plan: plan, fillsWidth: true) { state.openSession(for: plan) }
    }

    /// Says in one word whose plan this is. Without it the two are visually
    /// identical, and the difference decides whether the plan still follows
    /// the forecast.
    private var planOriginBadge: some View {
        PlanOriginBadge(isManual: isOwnPlan)
    }

    private var emptyPlanMessage: String {
        if plan.isCloudedOut {
            return "Clouded out — nothing to plan."
        }
        return "Nothing clears your minimum score for long enough on this night."
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
        PlanBlockRow(plan: plan, segment: segment)
            .contentShape(Rectangle())
            .onTapGesture { state.selectedTargetID = segment.targetID }
    }

    // MARK: - Mission summary

    /// The 2-3-second answer: is tonight worth it, when, at what, and why
    /// not more. Everything below this is the detail that backs it up.
    private var missionSummary: some View {
        HStack(alignment: .center, spacing: 16) {
            ScoreBadge(score: plan.score, size: 58)
            // Separate lines rather than one run-on sentence: when to shoot,
            // what to shoot, and what's limiting it each read as their own
            // thought.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(Format.longDate(plan.date, in: plan.timeZone))
                        .font(.scaled(.title2, scale: uiTextScale).weight(.bold))
                    VerdictTag(verdict: plan.verdict)
                    // A tag beside the verdict rather than a badge in its own
                    // corner, so nothing else in the card moves with it.
                    if plan.isCloudedOut {
                        Label("Clouded Out", systemImage: "cloud.rain.fill")
                            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                            .foregroundStyle(Palette.marginal)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Palette.marginal.opacity(0.15), in: Capsule())
                            .hoverTooltip("The forecast writes this night off.")
                    }
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
                    // Selecting it only changes what the Selected target
                    // panel shows — never the plan.
                    Button {
                        state.selectedTargetID = best.id
                    } label: {
                        HStack(spacing: 6) {
                            Text("Best target")
                                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                                .foregroundStyle(Palette.accent)
                            Text(bestTargetLine)
                                .font(.scaled(.callout, scale: uiTextScale).weight(.medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.right.circle")
                                .font(.scaled(.caption, scale: uiTextScale))
                                .foregroundStyle(Palette.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show details")
                    .accessibilityLabel("Best target, \(bestTargetLine). Show details")
                }
                if let limitation = nightLimitationPhrase(for: plan) {
                    let limitationLine = "Main limitation: \(limitation)"
                    Label(limitationLine, systemImage: "exclamationmark.circle")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        // Two lines: "waning gibbous moon" doesn't fit one
                        // beside the buttons on a laptop.
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .hoverTooltip(limitationLine)
                }
            }
            Spacer(minLength: 12)
            // The one thing to do next, in the same place every night; and
            // tonight, the screen for running it at the telescope, right
            // under it and the same width.
            VStack(spacing: 8) {
                Button {
                    state.openPlanner(for: plan)
                } label: {
                    Label("Plan Session", systemImage: "list.bullet.rectangle")
                        .font(.scaled(.body, scale: uiTextScale).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .help("Build this night's session")
                if state.canOpenSession(for: plan) {
                    sessionButton
                }
            }
            .controlSize(.large)
            .fixedSize(horizontal: true, vertical: false)
            // The big dome below says the same, larger.
            if !showsBigDome { skyDomeButton }
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

    /// Flows onto a second row when the column is narrow — whole stats move
    /// down rather than any of them being cut short or wrapped mid-value.
    private var statistics: some View {
        FlowLayout(spacing: 26, lineSpacing: 12) {
            LabelledValue(label: "Astronomical dark",
                          value: darkWindowText,
                          systemImage: "moon.stars")
            LabelledValue(label: "Moon down",
                          value: plan.moonlessDarkHours > 0.02 ? Format.hours(plan.moonlessDarkHours) : "none",
                          systemImage: plan.moon.symbolName)
            // The Moon card opens from Sky View's panel; the dome draws the
            // Moon itself.
            LabelledValue(label: "Moon",
                          value: "\(plan.moon.illuminationPercent)% \(plan.moon.phaseName.lowercased())",
                          systemImage: "circle.lefthalf.filled")
                .contentShape(Rectangle())
                .onTapGesture { isShowingMoon = true }
                .hoverTooltip("Click to see this night's Moon")
                .sheet(isPresented: $isShowingMoon) { MoonCard(plan: plan) }
            if plan.hasWeather {
                LabelledValue(label: "Cloud in the dark",
                              value: "\(Int(plan.meanCloudDuringDark))%",
                              systemImage: "cloud")
                LabelledValue(label: "Low",
                              value: Format.temperature(celsius: plan.minimumTemperature,
                                                        imperial: state.preferences.usesImperialUnits),
                              systemImage: "thermometer.low")
                if let dew = dewAssessment {
                    DewRiskValue(assessment: dew, timeZone: plan.timeZone,
                                 imperial: state.preferences.usesImperialUnits,
                                 explanation: dewExplanation(dew))
                }
                LabelledValue(label: "Gusts",
                              value: Format.wind(kilometersPerHour: plan.maximumGust,
                                                 imperial: state.preferences.usesImperialUnits),
                              systemImage: "wind")
            }
        }
    }

    private var darkWindowText: String {
        guard let dusk = plan.astronomicalDusk, let dawn = plan.astronomicalDawn else {
            return plan.darkWindows.isEmpty ? "none" : Format.hours(plan.darkHours)
        }
        return "\(Format.time(dusk, in: plan.timeZone))–\(Format.time(dawn, in: plan.timeZone))"
    }

    /// Whole items wrap onto a second row rather than being cut short —
    /// a truncated key tells you nothing, and it would otherwise be the
    /// first thing to make the automatic UI scale shrink everything.
    private var legend: some View {
        FlowLayout(spacing: 16, lineSpacing: 6) {
            legendItem(color: Palette.cloud.opacity(0.7), label: "cloud from the top")
            legendItem(color: Palette.moonlight.opacity(0.8), label: "moonlight and its altitude")
            legendItem(color: Palette.astronomical, label: "darker background = darker sky")
            if let target = selectedTargetPlan {
                legendItem(color: Palette.accent, label: "\(target.target.displayName)'s altitude · shaded box = its best window")
            }
            if let dew = dewAssessment {
                Label(dewAdviceLine(dew), systemImage: dew.level >= .high ? "drop.fill" : "drop")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(dew.level == .low ? Color.secondary : Palette.dewRisk(dew.level))
                    .lineLimit(1)
                    .hoverTooltip(dewExplanation(dew))
            }
        }
        .font(.scaled(.caption, scale: uiTextScale))
        .foregroundStyle(.secondary)
    }

    // MARK: - Dew risk

    /// The stretch dew risk is rated over: tonight's plan from its first
    /// block to its last, since that is when the scope is actually out, or
    /// astronomical darkness when there is no plan.
    private var dewSession: TimeWindow {
        let segments = planSegments.chronological
        if let first = segments.first, let last = segments.last {
            return TimeWindow(start: first.window.start, end: last.window.end)
        }
        if let dusk = plan.astronomicalDusk, let dawn = plan.astronomicalDawn {
            return TimeWindow(start: dusk, end: dawn)
        }
        return plan.chartWindow
    }

    private var dewAssessment: DewRisk.Assessment? {
        guard plan.hasWeather else { return nil }
        return DewRisk.assess(samples: plan.samples, over: dewSession)
    }

    /// Short enough for the legend row: the advice, and when it starts to
    /// matter.
    private func dewAdviceLine(_ dew: DewRisk.Assessment) -> String {
        guard dew.level > .low else { return dew.level.advice }
        return "\(dew.level.advice) \(dewWhen(dew))"
    }

    /// "all night" only when it really is — the worst level holding for the
    /// whole session — and otherwise when it starts, or when it eases.
    private func dewWhen(_ dew: DewRisk.Assessment) -> String {
        if dew.isWorstThroughout { return "all night" }
        if dew.peakStart <= dew.sessionStart.addingTimeInterval(10 * 60) {
            return "until \(Format.time(dew.peakEnd, in: plan.timeZone))"
        }
        return "after \(Format.time(dew.peakStart, in: plan.timeZone))"
    }

    /// The full reading, for hover: what, when and what to do. How it is
    /// worked out lives in Help, not here.
    private func dewExplanation(_ dew: DewRisk.Assessment) -> String {
        let imperial = state.preferences.usesImperialUnits
        let spread = Format.temperatureDelta(celsius: dew.spreadAtPeak, imperial: imperial)
        let when = dewWhen(dew)
        let reading: String
        switch dew.level {
        case .low:
            reading = "Temperature stays well clear of the dew point through the session."
        case _ where dew.peakIsRadiative:
            reading = "Clear, calm sky \(when): optics can cool below the air and dew over with the temperature still \(spread) above the dew point."
        case .moderate:
            reading = "Temperature comes within \(spread) of the dew point \(when)."
        case .high where dew.isWorstThroughout:
            reading = "Temperature stays close to the dew point all night."
        case .high:
            reading = "Risk is highest \(when), with the temperature close to the dew point."
        case .veryHigh:
            reading = "Temperature is expected to stay within \(spread) of the dew point \(when). Dew protection strongly recommended."
        }
        return "\(dew.level.name) dew risk. \(reading) \(dew.level.advice)."
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 14, height: 9)
                // A clear outline: the "darker sky" swatch is near-black and
                // vanished against the background with a faint one.
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.55), lineWidth: 1))
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

}

enum TargetSortOption: String, CaseIterable, Identifiable {
    case relevance = "Best Score"
    case longestWindow = "Longest Window"
    case bestTime = "Best Time"
    case alphabetical = "Alphabetical"
    case size = "Size in the Sky"

    var id: String { rawValue }

    /// Expects the planner's own order — score, highest first — as input.
    func sorted(_ targets: [TargetPlan]) -> [TargetPlan] {
        switch self {
        case .relevance:
            return targets
        case .longestWindow:
            return targets.sorted { $0.usableMinutes > $1.usableMinutes }
        case .bestTime:
            return targets.sorted { ($0.bestTime ?? .distantFuture) < ($1.bestTime ?? .distantFuture) }
        case .alphabetical:
            return targets.sorted { $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName) == .orderedAscending }
        case .size:
            return targets.sorted { $0.target.majorAxisArcminutes > $1.target.majorAxisArcminutes }
        }
    }
}

struct TargetRowView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan
    var targetPlan: TargetPlan
    var isSelected: Bool = false
    /// How many blocks of the plan being built point at this target.
    var plannedBlocks: Int = 0

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
                    if plannedBlocks > 0 {
                        Label(plannedBlocks > 1 ? "Planned ×\(plannedBlocks)" : "Planned",
                              systemImage: "checkmark.circle.fill")
                            .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .fixedSize()
                    }
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
                            .hoverTooltip("Zenith risk from \(Format.time(risk.start, in: plan.timeZone))")
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
        // An outline as well as the tint: it stays visible when the window
        // isn't key and doesn't rely on colour alone.
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Palette.accent : Color.clear, lineWidth: 1.5))
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sheet(isPresented: $isShowingCatalogDetail) {
            TargetCatalogDetail(target: targetPlan.target, night: plan)
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

/// Dew risk in the statistics row: a coloured level, and the tightest
/// temperature/dew-point spread in the session with when it comes.
private struct DewRiskValue: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var assessment: DewRisk.Assessment
    var timeZone: TimeZone
    var imperial: Bool
    var explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "drop")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.accent)
                Text("Dew risk")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.dewRisk(assessment.level))
                    .frame(width: 10 * uiTextScale, height: 10 * uiTextScale)
                Text(assessment.level.name)
                    .font(.scaled(.title3, scale: uiTextScale).weight(.medium))
                    .lineLimit(1)
            }
            Text("min \(Format.temperatureDelta(celsius: assessment.minimumSpread, imperial: imperial)) at \(Format.time(assessment.minimumSpreadTime, in: timeZone))")
                .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .hoverTooltip(explanation)
    }
}

/// A bar on the night chart's own time axis, coloured by dew risk as it
/// changes, so a night that starts dry and turns wet towards morning reads
/// at a glance. Hovering it reads out that moment and the key.
private struct DewRiskStrip: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var plan: NightPlan
    var imperial: Bool
    /// See `NightTimelineView.isScrolling`: hover fires as content scrolls
    /// under a still cursor, and answering it mid-scroll fights the scroll.
    var isScrolling: Bool

    @State private var hoverX: CGFloat?

    /// How far either side of a change the colours blend, so a change reads
    /// as the gradual thing it is rather than a hard edge at one sample.
    private static let blendMinutes: Double = 20

    var body: some View {
        GeometryReader { geometry in
            let axis = TimeAxis(window: plan.chartWindow, width: geometry.size.width)
            Canvas { context, size in
                let bar = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                let stops = gradientStops(axis: axis, width: size.width)
                guard stops.count > 1 else { return }
                context.fill(bar, with: .linearGradient(Gradient(stops: stops),
                                                        startPoint: .zero,
                                                        endPoint: CGPoint(x: size.width, y: 0)))
            }
            .frame(height: 6 * uiTextScale)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard !isScrolling else { hoverX = nil; return }
                switch phase {
                case .active(let location): hoverX = location.x
                case .ended: hoverX = nil
                }
            }
            .onChange(of: isScrolling) { _, scrolling in if scrolling { hoverX = nil } }
            .overlay(alignment: .bottomLeading) {
                if let hoverX, let sample = sample(at: axis.date(for: hoverX)),
                   let conditions = DewRisk.conditions(of: sample) {
                    let cardWidth = 250 * uiTextScale
                    readout(time: sample.date, conditions: conditions)
                        .frame(width: cardWidth, alignment: .leading)
                        .offset(x: clamp(hoverX - cardWidth / 2, 0, max(0, geometry.size.width - cardWidth)),
                                y: -geometry.size.height - 4)
                        .allowsHitTesting(false)
                }
            }
        }
        // Taller than the bar itself, so it can be hovered without
        // pixel-hunting a 6pt line.
        .frame(height: 14 * uiTextScale)
    }

    private func sample(at date: Date) -> NightSample? {
        plan.samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// One stop per sample, each the average colour of the samples within
    /// `blendMinutes` of it — a box blur along the night, so steady stretches
    /// stay their own colour and changes fade across the blend width.
    private func gradientStops(axis: TimeAxis, width: CGFloat) -> [Gradient.Stop] {
        guard width > 0 else { return [] }
        let rated: [(Date, SIMD3<Double>)] = plan.samples.compactMap { sample in
            DewRisk.level(of: sample).map { (sample.date, Self.rgb(Palette.dewRisk($0))) }
        }
        let reach = Self.blendMinutes * 60
        return rated.map { date, _ in
            let near = rated.filter { abs($0.0.timeIntervalSince(date)) <= reach }.map(\.1)
            let mean = near.reduce(SIMD3<Double>(repeating: 0), +) / Double(near.count)
            return Gradient.Stop(color: Color(red: mean.x, green: mean.y, blue: mean.z),
                                 location: axis.x(for: date) / width)
        }
    }

    private static func rgb(_ color: Color) -> SIMD3<Double> {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        return SIMD3(resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
    }

    private func readout(time: Date, conditions: DewConditions) -> some View {
        let level = DewRisk.level(for: conditions)
        let spread = Format.temperatureDelta(celsius: conditions.spreadCelsius, imperial: imperial)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Palette.dewRisk(level)).frame(width: 9, height: 9)
                Text("\(Format.time(time, in: plan.timeZone)) · \(level.name) dew risk")
                    .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
            }
            Text(spreadNote(spread: spread, conditions: conditions, level: level))
                .font(.scaled(.caption2, scale: uiTextScale))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Color.white.opacity(0.2))
            ForEach(DewRiskLevel.allCases, id: \.self) { key in
                HStack(spacing: 6) {
                    Circle().fill(Palette.dewRisk(key)).frame(width: 7, height: 7)
                    Text(key.name)
                        .font(.scaled(.caption2, scale: uiTextScale).weight(key == level ? .bold : .regular))
                        .frame(width: 62 * uiTextScale, alignment: .leading)
                    Text(bandText(key))
                        .font(.scaled(.caption2, scale: uiTextScale))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        // Opaque: it sits over the chart, whose labels showed through.
        .background(Color.black, in: RoundedRectangle(cornerRadius: 7))
    }

    /// The spread, and the clear-and-calm step only when it actually moved
    /// the rating — a spread that is already Very High has nowhere to go.
    private func spreadNote(spread: String, conditions: DewConditions, level: DewRiskLevel) -> String {
        if DewRisk.favoursRadiativeCooling(conditions),
           DewRisk.baseLevel(spreadCelsius: conditions.spreadCelsius) < level {
            return "Air \(spread) above its dew point, under a clear, calm sky — optics cool below the air, so one step higher."
        }
        return "Air \(spread) above its dew point."
    }

    /// The spread band for each level, in the units you've chosen.
    private func bandText(_ level: DewRiskLevel) -> String {
        func delta(_ celsius: Double) -> String {
            imperial ? String(format: "%.0f°F", celsius * 9 / 5) : String(format: "%.1f°C", celsius)
        }
        switch level {
        case .low: return "spread over \(delta(DewRisk.lowAbove))"
        case .moderate: return "\(delta(DewRisk.moderateAbove))–\(delta(DewRisk.lowAbove))"
        case .high: return "\(delta(DewRisk.highAbove))–\(delta(DewRisk.moderateAbove))"
        case .veryHigh: return "\(delta(DewRisk.highAbove)) or less"
        }
    }
}

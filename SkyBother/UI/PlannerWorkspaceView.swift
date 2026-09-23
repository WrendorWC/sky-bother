import SwiftUI

/// Where a night's session gets built. Everything needed to build it stays on
/// screen together: the night's context along the top, the timeline being
/// edited, the candidates to choose from, the selected target, and the
/// actions that save or discard the result. Only the candidate list scrolls.
///
/// Edits go to `AppState.planDraft` and nowhere else until Done, so leaving
/// by any other route — Home, Cancel, Esc — either discards the draft or,
/// when it holds real changes, asks first.
struct PlannerWorkspaceView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    var plan: NightPlan

    @State private var sortOption: TargetSortOption = .relevance
    @State private var minimumUsableHours: Double = 0
    @State private var fitsFrameOnly = false
    /// The block the keyboard acts on. Separate from the selected target:
    /// a target can hold several blocks.
    @State private var selectedBlockID: UUID?
    /// The block mid-drag, as it would land if dropped now.
    @State private var dragReadout: PlanSegment?
    /// What the last Add did, in words — where the block went and anything
    /// wrong with it.
    @State private var addNote: String?
    @State private var isConfirmingReset = false
    @State private var isConfirmingLeave = false
    @State private var isConfirmingRevert = false
    @State private var compactPane: CompactPane = .candidates
    @FocusState private var isTimelineFocused: Bool
    /// Remembered between launches: how wide you like the inspector.
    /// 0 until you drag the divider: the default then follows the UI scale.
    @AppStorage("plannerInspectorWidth") private var inspectorWidthSetting: Double = 0

    private enum CompactPane: String, CaseIterable, Identifiable {
        case candidates = "Candidates"
        case details = "Details"
        var id: String { rawValue }
    }

    private var draft: PlanDraft? { state.planDraft }
    private var segments: [PlanSegment] { state.displayedPlan(for: plan) }
    private var isDirty: Bool { draft?.isDirty ?? false }

    private var candidates: [TargetPlan] {
        var list = state.visibleTargets(for: plan)
        if minimumUsableHours > 0 {
            list = list.filter { $0.usableMinutes >= minimumUsableHours * 60 }
        }
        if fitsFrameOnly {
            list = list.filter { !$0.fit.needsMosaic && $0.fit.fillFraction >= 0.10 }
        }
        return sortOption.sorted(list)
    }

    private var selectedTarget: TargetPlan? {
        guard let id = state.selectedTargetID else { return nil }
        return plan.targets.first { $0.id == id }
    }

    private var selectedBlock: PlanSegment? {
        guard let selectedBlockID else { return nil }
        return segments.first { $0.id == selectedBlockID }
    }

    /// Changes whenever the app's own suggestion does, so an untouched draft
    /// can follow it.
    private var suggestionKey: [String] {
        state.suggestedPlan(for: plan).map {
            "\($0.targetID)@\($0.window.start.timeIntervalSince1970)-\($0.window.end.timeIntervalSince1970)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            contextHeader
            Divider()
            timelinePanel
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            lowerRegion
            Divider()
            actionBar
        }
        .spaceBackground()
        .navigationTitle("Plan session")
        .onEscapeKey { escape() }
        .onChange(of: suggestionKey) { _, _ in state.reseedDraftIfPristine(for: plan) }
        // A block added from the catalog gets the same selection and note as
        // one added here.
        .onAppear { adoptBlockAddedElsewhere() }
        .onChange(of: state.blockAddedElsewhere) { _, _ in adoptBlockAddedElsewhere() }
        .confirmationDialog(leaveTitle, isPresented: $isConfirmingLeave) {
            Button("Save plan") { done() }
            Button("Discard changes", role: .destructive) {
                state.cancelEditingPlan()
                state.closePlanner()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Saving makes this a manual plan.")
        }
        .confirmationDialog("Discard your changes?", isPresented: $isConfirmingRevert) {
            Button("Discard changes", role: .destructive) {
                state.revertDraft()
                selectedBlockID = nil
                addNote = "Changes discarded."
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("The plan goes back to how it was when you opened the planner.")
        }
        .confirmationDialog(resetTitle, isPresented: $isConfirmingReset) {
            Button("Reset manual plan", role: .destructive) {
                state.resetPlanToSuggested(for: plan)
                selectedBlockID = nil
                addNote = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your manual plan will be replaced by the current suggestion.")
        }
    }

    // MARK: - Context

    /// The night, where and with what — never scrolls away.
    private var contextHeader: some View {
        HStack(spacing: 14) {
            Button(action: leave) {
                Label("Home", systemImage: "chevron.left")
                    .font(.scaled(.body, scale: uiTextScale))
            }
            .help("Back to Home")

            ScoreBadge(score: plan.score, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(Format.longDate(plan.date, in: plan.timeZone))
                        .font(.scaled(.title3, scale: uiTextScale).weight(.bold))
                    VerdictTag(verdict: plan.verdict)
                }
                Text(nightLine)
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .hoverTooltip(nightLine)
            }
            Spacer(minLength: 12)
            Button {
                state.openSkyView(for: plan)
            } label: {
                Label("Sky View", systemImage: "circle.dashed.inset.filled")
                    .font(.scaled(.body, scale: uiTextScale))
            }
            .help("See this plan on the sky")
            VStack(alignment: .trailing, spacing: 3) {
                Label(plan.site.name, systemImage: "mappin.and.ellipse")
                Label(state.rig.name, systemImage: "camera.aperture")
            }
            .font(.scaled(.callout, scale: uiTextScale))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.spaceTop)
    }

    private var nightLine: String {
        var parts: [String] = []
        if let window = plan.bestImagingWindow, !window.isEmpty {
            parts.append("Best imaging \(Format.time(window.start, in: plan.timeZone))–\(Format.time(window.end, in: plan.timeZone))")
        } else {
            parts.append(plan.headline)
        }
        if let limitation = nightLimitationPhrase(for: plan) {
            parts.append("Main limitation: \(limitation)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Timeline

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SectionHeader("Session timeline")
                Spacer()
                Text(timelineSummary)
                    .font(.scaled(.caption, scale: uiTextScale).monospacedDigit())
                    .foregroundStyle(unshootableMinutes > 0 ? Palette.marginal : .secondary)
            }

            HourAxisLabels(window: plan.chartWindow, timeZone: plan.timeZone)

            PlanStripView(plan: plan, segments: segments, isEditing: true,
                          selectedSegmentID: selectedBlockID,
                          onSelect: { segment in
                              selectedBlockID = segment.id
                              isTimelineFocused = true
                          },
                          onDragReadout: { dragReadout = $0 },
                          onCommit: {
                              state.updateDraft($0)
                              addNote = nil
                          })
                .frame(height: 52 * max(1, uiTextScale * 0.9))
                .focusable()
                .focused($isTimelineFocused)
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .deleteForward]) { press in
                    handleKey(press)
                }
                .accessibilityElement()
                .accessibilityLabel("Session timeline")
                .accessibilityValue(timelineAccessibilitySummary)
                .accessibilityHint("Arrow keys move the selected block by five minutes. Shift-arrows change its end, Option-arrows its start. Up and down arrows pick a block. Delete removes it.")

            // Always the same height, selected target or not, so the list
            // below doesn't jump each time the selection comes and goes.
            Group {
                if let selectedTarget {
                    TargetAvailabilityBar(plan: plan, targetPlan: selectedTarget, height: 12)
                        .overlay(alignment: .leading) {
                            Text("\(selectedTarget.target.displayName) usable")
                                .font(.scaled(.caption2, scale: uiTextScale).weight(.semibold))
                                .padding(.horizontal, 4)
                                .background(Palette.spaceTop.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                                .padding(.leading, 2)
                        }
                        .help("When \(selectedTarget.target.displayName) is up, dark and clear enough to shoot")
                } else {
                    Text("Select a target to see when it's usable")
                        .font(.scaled(.caption2, scale: uiTextScale))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: max(12, 13 * uiTextScale))

            timelineStatus
        }
    }

    /// Live drag times while dragging, otherwise the selected block, the
    /// result of the last Add, or how the strip works.
    @ViewBuilder
    private var timelineStatus: some View {
        HStack(spacing: 12) {
            timelineMessage
                .frame(maxWidth: .infinity, alignment: .leading)
            if selectedBlock != nil && dragReadout == nil {
                Button(action: removeSelectedBlock) {
                    Label("Remove block", systemImage: "minus.circle")
                        .font(.scaled(.callout, scale: uiTextScale))
                }
                .buttonStyle(.bordered)
                .help("Take the selected block out of the plan (Delete)")
            }
        }
    }

    @ViewBuilder
    private var timelineMessage: some View {
        Group {
            if let dragReadout {
                Label(blockDescription(dragReadout), systemImage: "arrow.left.and.right")
                    .foregroundStyle(Palette.accent)
            } else if let addNote {
                Label(addNote, systemImage: "plus.circle")
            } else if let selectedBlock {
                Label(blockDescription(selectedBlock), systemImage: "rectangle.inset.filled")
            } else if segments.isEmpty {
                Text("Nothing planned yet. Add a target below.")
            } else {
                Text("Drag a block to move it, or an edge to resize. Arrow keys nudge the selected block. Hatching marks unshootable time.")
            }
        }
        .font(.scaled(.caption, scale: uiTextScale))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(minHeight: 16 * uiTextScale, alignment: .leading)
    }

    private func blockDescription(_ segment: PlanSegment) -> String {
        let times = "\(Format.time(segment.window.start, in: plan.timeZone))–\(Format.time(segment.window.end, in: plan.timeZone))"
        var text = "\(segment.targetName) · \(times) · \(Format.duration(minutes: segment.window.durationMinutes))"
        if let unshootable = unshootableDescription(segment) { text += " · \(unshootable)" }
        return text
    }

    private func unshootableDescription(_ segment: PlanSegment) -> String? {
        let targetPlan = plan.targets.first { $0.id == segment.targetID }
        let fragments = segment.unusableFragments(against: targetPlan)
        guard fragments.totalMinutes > 0 else { return nil }
        guard let targetPlan else { return "not available at all this night" }
        return "\(Format.duration(minutes: fragments.totalMinutes)) unshootable — \(Shootability.causes(of: fragments, for: targetPlan.target, in: plan, minimumAltitude: state.preferences.minimumUsefulAltitude))"
    }

    private var unshootableMinutes: Double {
        segments.reduce(0) { total, segment in
            total + segment.unusableMinutes(against: plan.targets.first { $0.id == segment.targetID })
        }
    }

    private var timelineSummary: String {
        guard !segments.isEmpty else { return "No blocks" }
        let blocks = "\(segments.count) block\(segments.count == 1 ? "" : "s")"
        let hours = Format.hours(segments.totalMinutes / 60)
        guard unshootableMinutes > 0 else { return "\(blocks) · \(hours)" }
        return "\(blocks) · \(hours) · \(Format.duration(minutes: unshootableMinutes)) unshootable"
    }

    private var timelineAccessibilitySummary: String {
        guard !segments.isEmpty else { return "No blocks planned" }
        return segments.map { blockDescription($0) }.joined(separator: "; ")
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let ordered = segments.chronological
        guard !ordered.isEmpty else { return .ignored }

        switch press.key {
        case .upArrow, .downArrow:
            let index = selectedBlock.flatMap { block in ordered.firstIndex { $0.id == block.id } }
            let next: Int
            if let index {
                next = press.key == .upArrow ? max(0, index - 1) : min(ordered.count - 1, index + 1)
            } else {
                next = press.key == .upArrow ? ordered.count - 1 : 0
            }
            select(ordered[next])
            return .handled
        case .delete, .deleteForward:
            guard selectedBlock != nil else { return .ignored }
            removeSelectedBlock()
            return .handled
        case .leftArrow, .rightArrow:
            guard let block = selectedBlock else {
                select(ordered[0])
                return .handled
            }
            let step = SessionPlanRules.snapMinutes * 60 * (press.key == .leftArrow ? -1 : 1)
            let night = plan.chartWindow
            let edited: PlanSegment
            let isMove: Bool
            if press.modifiers.contains(.shift) {
                edited = SessionPlanRules.resized(block, movingStart: false, by: step, within: night)
                isMove = false
            } else if press.modifiers.contains(.option) {
                edited = SessionPlanRules.resized(block, movingStart: true, by: step, within: night)
                isMove = false
            } else {
                edited = SessionPlanRules.moved(block, by: step, within: night)
                isMove = true
            }
            if let resolved = SessionPlanRules.resolve(dragged: edited, against: ordered,
                                                       within: night, allowSwap: isMove) {
                state.updateDraft(resolved)
                addNote = nil
            }
            return .handled
        default:
            return .ignored
        }
    }

    private func select(_ segment: PlanSegment) {
        selectedBlockID = segment.id
        state.selectedTargetID = segment.targetID
        addNote = nil
    }

    private func remove(_ targetPlan: TargetPlan) {
        let count = segments.filter { $0.targetID == targetPlan.id }.count
        guard count > 0 else { return }
        state.removeDraftSegments(forTarget: targetPlan.id)
        if let selectedBlockID, !segments.contains(where: { $0.id == selectedBlockID }) {
            self.selectedBlockID = nil
        }
        addNote = count == 1 ? "Removed \(targetPlan.target.displayName)." : "Removed \(count) blocks of \(targetPlan.target.displayName)."
    }

    private func removeSelectedBlock() {
        guard let block = selectedBlock else { return }
        let ordered = segments.chronological
        let index = ordered.firstIndex { $0.id == block.id } ?? 0
        state.removeDraftSegment(id: block.id)
        let remaining = segments.chronological
        selectedBlockID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        addNote = "Removed \(block.targetName)."
    }

    // MARK: - Candidates and inspector

    private var lowerRegion: some View {
        GeometryReader { geometry in
            // The inspector grows with the UI scale; side by side only while
            // the candidate rows still get enough room beside it.
            let inspectorMinimum = 320 * max(1, uiTextScale * 0.9)
            if geometry.size.width - inspectorMinimum >= 480 * uiTextScale {
                // Drag the divider to trade list width for inspector width.
                ResizableSplit(trailingWidth: Binding(get: { inspectorWidthSetting > 0 ? inspectorWidthSetting : 400 * uiTextScale },
                                                      set: { inspectorWidthSetting = $0 }),
                               trailingRange: inspectorMinimum...1100,
                               leadingMinimum: 480 * uiTextScale) {
                    candidatesPane
                } trailing: {
                    inspectorPane
                }
            } else {
                // Narrow, or a large UI scale: one pane at a time rather than
                // both squeezed until neither reads.
                VStack(spacing: 0) {
                    Picker("Show", selection: $compactPane) {
                        ForEach(CompactPane.allCases) { pane in Text(pane.rawValue).tag(pane) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    Divider()
                    if compactPane == .candidates { candidatesPane } else { inspectorPane }
                }
            }
        }
    }

    private var candidatesPane: some View {
        VStack(spacing: 0) {
            constraintsBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Palette.panel)
            Divider()
            if candidates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "binoculars")
                        .font(.system(size: 40 * uiTextScale))
                        .foregroundStyle(Palette.accent.opacity(0.7))
                    Text("No candidates")
                        .font(.scaled(.title3, scale: uiTextScale).weight(.semibold))
                    Text(emptyCandidatesMessage)
                        .font(.scaled(.body, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    catalogButton(search: state.searchText)
                        .padding(.top, 6)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(candidates) { targetPlan in
                            candidateRow(targetPlan)
                            Divider().padding(.leading, 20)
                        }
                        catalogFooter
                    }
                }
                .scrollIndicators(.visible)
            }
        }
    }

    /// The end of the list isn't the end of the sky: this list only holds
    /// what clears your minimum score on this night.
    private var catalogFooter: some View {
        VStack(spacing: 8) {
            Text("That's every target scoring \(Int(state.preferences.minimumScore)) or more on this night.")
                .font(.scaled(.callout, scale: uiTextScale))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            catalogButton(search: nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    /// Opens the catalog on this night — carrying the search over when there
    /// is one, so a target missing here can be looked up there.
    private func catalogButton(search: String?) -> some View {
        let trimmed = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Button {
            state.catalogRequest = AppState.CatalogRequest(nightID: plan.id, search: trimmed.isEmpty ? nil : trimmed)
            AppWindow.bringForward(id: "catalog", using: openWindow)
        } label: {
            Label(trimmed.isEmpty ? "Browse full catalog" : "Search the full catalog for \u{201c}\(trimmed)\u{201d}",
                  systemImage: "photo.on.rectangle.angled")
                .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
        }
        .buttonStyle(.bordered)
        .help("Every target, scored for this night")
    }

    private var emptyCandidatesMessage: String {
        if plan.darkWindows.isEmpty {
            return "The sun never gets far enough below the horizon at this latitude and date."
        }
        let search = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty && state.typeFilter.isEmpty && minimumUsableHours == 0 && !fitsFrameOnly {
            return "Nothing here matches \u{201c}\(search)\u{201d}. This list only has targets above your minimum score."
        }
        if !search.isEmpty || !state.typeFilter.isEmpty || minimumUsableHours > 0 || fitsFrameOnly {
            return "Nothing matches these filters."
        }
        return "Nothing clears your minimum score."
    }

    /// The constraints: what the suggestion favours, and which candidates to
    /// show — by name, type, usable time and whether they fit the frame.
    private var constraintsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search targets", text: $state.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.panelBorder))
                .frame(minWidth: 150)

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
                .scaledMenuStyle(uiTextScale)

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
                .scaledMenuStyle(uiTextScale)
            }

            HStack(spacing: 14) {
                Menu {
                    Picker("Usable for at least", selection: $minimumUsableHours) {
                        Text("Any time").tag(0.0)
                        Text("1 hour").tag(1.0)
                        Text("2 hours").tag(2.0)
                        Text("3 hours").tag(3.0)
                        Text("4 hours").tag(4.0)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(minimumUsableHours == 0 ? "Any usable time" : "At least \(Int(minimumUsableHours))h usable",
                          systemImage: "clock")
                }
                .scaledMenuStyle(uiTextScale)
                .help("Only show targets usable for at least this long this night")

                Toggle("Fits my frame", isOn: $fitsFrameOnly)
                    .toggleStyle(.checkbox)
                    .help("Hide targets that overflow the frame or are tiny in it (under 10% of the long side)")

                Menu {
                    Picker("Suggestion favours", selection: $state.preferences.planEmphasis) {
                        ForEach(PlanEmphasis.allCases, id: \.self) { emphasis in
                            Text(emphasis.title).tag(emphasis)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Suggestion: \(state.preferences.planEmphasis.title.lowercased())", systemImage: "wand.and.stars")
                }
                .scaledMenuStyle(uiTextScale)
                .help("How the suggested plan is built. Your edits are kept.")

                Spacer(minLength: 0)

                if state.isPlanning {
                    ProgressView().controlSize(.small)
                }
                Text("\(candidates.count) target\(candidates.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }

    private func candidateRow(_ targetPlan: TargetPlan) -> some View {
        let planned = segments.filter { $0.targetID == targetPlan.id }.count
        return HStack(spacing: 10) {
            TargetRowView(plan: plan, targetPlan: targetPlan,
                          isSelected: state.selectedTargetID == targetPlan.id,
                          plannedBlocks: planned)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.selectedTargetID = targetPlan.id
                    selectedBlockID = nil
                    addNote = nil
                }
            Button {
                add(targetPlan)
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
            }
            .buttonStyle(.bordered)
            .help(planned == 0
                  ? "Add to the longest free stretch of the night"
                  : "Add another block")
            .accessibilityLabel("Add \(targetPlan.target.displayName) to plan")
            // Always laid out, hidden when unplanned, so every row keeps the
            // same width and the availability bars stay lined up.
            Button {
                remove(targetPlan)
            } label: {
                Label("Remove", systemImage: "minus")
                    .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
            }
            .buttonStyle(.bordered)
            .opacity(planned > 0 ? 1 : 0)
            .disabled(planned == 0)
            .accessibilityHidden(planned == 0)
            .help(planned == 1 ? "Take this target out of the plan" : "Take all \(planned) of this target's blocks out of the plan")
            .accessibilityLabel("Remove \(targetPlan.target.displayName) from plan")
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var inspectorPane: some View {
        if let selectedTarget {
            TargetDetailView(plan: plan, targetPlan: selectedTarget,
                             onAddToPlan: { add(selectedTarget) },
                             onRemoveFromPlan: { remove(selectedTarget) },
                             framingHeight: 180,
                             setsWindowTitle: false)
                .id(selectedTarget.id)
        } else {
            EmptyStateView(title: "Pick a candidate",
                           message: "Select a target to see how it fits this night.",
                           systemImage: "scope")
        }
    }

    // MARK: - Actions

    private func add(_ targetPlan: TargetPlan) {
        guard let segment = state.addDraftSegment(for: targetPlan, in: plan) else {
            addNote = "No room left in the night for \(targetPlan.target.displayName) — shorten or remove a block first."
            return
        }
        announce(segment, for: targetPlan)
    }

    private func adoptBlockAddedElsewhere() {
        guard let segment = state.blockAddedElsewhere else { return }
        state.blockAddedElsewhere = nil
        guard let targetPlan = plan.targets.first(where: { $0.id == segment.targetID }) else { return }
        announce(segment, for: targetPlan)
    }

    /// Selects a newly added block and says where it went, and anything
    /// wrong with where it had to go.
    private func announce(_ segment: PlanSegment, for targetPlan: TargetPlan) {
        selectedBlockID = segment.id
        state.selectedTargetID = segment.targetID
        var note = "Added \(targetPlan.target.displayName) at \(Format.time(segment.window.start, in: plan.timeZone))–\(Format.time(segment.window.end, in: plan.timeZone))."
        if let unshootable = unshootableDescription(segment) {
            note += " \(unshootable)."
            // The scheduler only falls back to unusable time when every
            // stretch the target could use is already taken.
            if targetPlan.usableMinutes > 0,
               segment.unusableMinutes(against: targetPlan) >= segment.window.durationMinutes * 0.5 {
                note += " Its usable time is taken by other blocks."
            }
        }
        addNote = note
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            PlanOriginBadge(isManual: draft?.originalIsManual ?? state.isManualPlan(for: plan))
            Label(isDirty ? "Unsaved changes" : "No unsaved changes",
                  systemImage: isDirty ? "pencil.circle.fill" : "checkmark.circle")
                .foregroundStyle(isDirty ? Palette.marginal : .secondary)

            if let reset = state.recentReset, reset.planKey == plan.planKey {
                Text("Manual plan removed.")
                    .foregroundStyle(.secondary)
                Button { state.undoPlanReset() } label: { Text("Undo").font(.scaled(.callout, scale: uiTextScale)) }
                    .buttonStyle(.link)
            }

            Spacer(minLength: 12)

            if state.isManualPlan(for: plan) {
                Button { isConfirmingReset = true } label: { Text("Reset manual plan").font(.scaled(.callout, scale: uiTextScale)) }
                    .help("Replace your manual plan with the current suggestion")
            }
            Button {
                state.clearDraft()
                selectedBlockID = nil
                addNote = "Draft cleared."
            } label: {
                Text("Clear draft").font(.scaled(.callout, scale: uiTextScale))
            }
            .disabled(segments.isEmpty)
            .help("Empty the plan. Nothing is saved until Done.")

            Button { leave() } label: { Text("Cancel").font(.scaled(.callout, scale: uiTextScale)) }
                .help("Close without saving")

            Button(action: done) {
                Text("Done").font(.scaled(.callout, scale: uiTextScale).weight(.semibold)).frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help(isDirty
                  ? "Save as this night's manual plan (⌘↩)"
                  : "Close — nothing to save (⌘↩)")
        }
        .font(.scaled(.callout, scale: uiTextScale))
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Palette.spaceTop)
    }

    private var leaveTitle: String {
        "Save changes to the plan for \(Format.longDate(plan.date, in: plan.timeZone))?"
    }

    private var resetTitle: String {
        "Reset the plan for \(Format.longDate(plan.date, in: plan.timeZone))?"
    }

    /// Esc undoes rather than leaves when there's something to undo: with
    /// changes, it offers to put the plan back and stays; with none, it
    /// closes the planner like Cancel.
    private func escape() {
        if isDirty {
            isConfirmingRevert = true
        } else {
            leave()
        }
    }

    /// Home and Cancel come here. Nothing to lose closes straight
    /// away; real changes ask whether to keep them.
    private func leave() {
        if isDirty {
            isConfirmingLeave = true
        } else {
            state.cancelEditingPlan()
            state.closePlanner()
        }
    }

    private func done() {
        state.finishEditingPlan()
        state.closePlanner()
    }
}

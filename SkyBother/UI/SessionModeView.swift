import SwiftUI

/// Tonight's plan at the telescope: what's on now, how long is left, what's
/// next, and only the warnings worth acting on. Large type on a dim
/// red-black background, readable at a glance without spoiling dark
/// adaptation more than a screen must.
///
/// It follows the clock and the plan and needs nothing from you — your
/// telescope's own app is where the night is actually run.
struct SessionModeView: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @EnvironmentObject private var state: AppState
    var plan: NightPlan

    private static let background = Color(red: 0.035, green: 0.02, blue: 0.03)
    private static let panel = Color(red: 0.09, green: 0.05, blue: 0.06)
    private static let border = Color(red: 0.27, green: 0.15, blue: 0.18)
    private static let text = Color(red: 1.0, green: 0.93, blue: 0.93)
    private static let muted = Color(red: 0.80, green: 0.66, blue: 0.68)
    private static let accent = Color(red: 0.86, green: 0.30, blue: 0.30)
    private static let warning = Color(red: 0.95, green: 0.70, blue: 0.40)

    private var segments: [PlanSegment] { state.displayedPlan(for: plan) }

    var body: some View {
        // Once a second is plenty for elapsed and remaining minutes.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header
                Divider().overlay(Self.border)
                let clock = SessionClock(at: context.date, plan: segments)
                VStack(spacing: 14) {
                    mainPanel(clock, now: context.date)
                        .frame(maxHeight: .infinity)
                    HStack(alignment: .top, spacing: 14) {
                        conditions(now: context.date)
                        about(clock)
                        upNext(clock, now: context.date)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .onAppear { follow(clock) }
                .onChange(of: (clock.current ?? clock.next)?.targetID) { _, _ in follow(clock) }
            }
        }
        .foregroundStyle(Self.text)
        .background(Self.background)
        .navigationTitle("Session")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: state.leaveSession) {
                Label("Home", systemImage: "chevron.left")
                    .font(.scaled(.body, scale: uiTextScale))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Self.muted)
            .help("Back to Home")

            VStack(alignment: .leading, spacing: 2) {
                Text("Session")
                    .font(.scaled(.title3, scale: uiTextScale).weight(.bold))
                Text("\(Format.longDate(plan.date, in: plan.timeZone)) · \(plan.site.name)")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(Self.muted)
            }
            Spacer()
            Text(Format.time(Date(), in: plan.timeZone))
                .font(.scaled(.title2, scale: uiTextScale).monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Self.panel)
    }

    // MARK: - Now

    @ViewBuilder
    private func mainPanel(_ clock: SessionClock, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch clock.phase {
            case .running:
                if let block = clock.current { blockDetail(block, heading: "NOW", now: now, isRunning: true) }
            case .notStarted, .between:
                if let block = clock.next {
                    blockDetail(block, heading: "NEXT · STARTS IN \(countdown(to: block.window.start, from: now))",
                                now: now, isRunning: false)
                }
            case .finished:
                Text("Tonight's plan is finished")
                    .font(.system(size: 40 * uiTextScale, weight: .bold))
                Text("The last block ended at \(segments.last.map { Format.time($0.window.end, in: plan.timeZone) } ?? "").")
                    .font(.scaled(.title3, scale: uiTextScale))
                    .foregroundStyle(Self.muted)
                liveDome(now: now)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Self.border))
    }

    @ViewBuilder
    private func blockDetail(_ block: PlanSegment, heading: String, now: Date, isRunning: Bool) -> some View {
        let targetPlan = plan.targets.first { $0.id == block.targetID }
        let times = "\(Format.time(block.window.start, in: plan.timeZone))–\(Format.time(block.window.end, in: plan.timeZone))"
        Text(heading)
            .font(.scaled(.callout, scale: uiTextScale).weight(.semibold))
            .kerning(0.8)
            .foregroundStyle(Self.accent)
        Text(block.targetName)
            .font(.system(size: 44 * uiTextScale, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        if isRunning {
            let elapsed = now.timeIntervalSince(block.window.start)
            Text("\(times) · \(Format.duration(minutes: max(0, block.window.end.timeIntervalSince(now)) / 60)) left")
                .font(.scaled(.title3, scale: uiTextScale).monospacedDigit())
                .foregroundStyle(Self.muted)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Self.border)
                    Capsule().fill(Self.accent)
                        .frame(width: geometry.size.width * CGFloat(min(1, max(0, elapsed / max(1, block.window.duration)))))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        } else {
            Text("\(times) · \(Format.duration(minutes: block.window.durationMinutes))")
                .font(.scaled(.title3, scale: uiTextScale).monospacedDigit())
                .foregroundStyle(Self.muted)
        }
        if let targetPlan {
            // Split: what you're capturing, and where it is right now.
            // Two equal boxes, so neither outweighs the other.
            HStack(alignment: .top, spacing: 12) {
                viewBox("In your frame") {
                    FramingPreview(target: targetPlan.target, rig: state.rig)
                }
                liveDome(now: now)
            }
            .frame(maxHeight: .infinity)
            if isRunning,
               let reason = Shootability.reason(for: targetPlan.target, at: now, in: plan,
                                                minimumAltitude: state.preferences.minimumUsefulAltitude) {
                Label("Right now it's \(reason.phrase).", systemImage: "exclamationmark.triangle.fill")
                    .font(.scaled(.callout, scale: uiTextScale))
                    .foregroundStyle(Self.warning)
            }
        }
    }

    /// The dome marks the selected target, so keep it on the block that's
    /// on now, or the next one.
    private func follow(_ clock: SessionClock) {
        if let id = (clock.current ?? clock.next)?.targetID, state.selectedTargetID != id {
            state.selectedTargetID = id
        }
    }

    /// Where it is right now: the dome at the current minute, with the
    /// target marked.
    private func liveDome(now: Date) -> some View {
        let minute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return viewBox("In the sky now · \(Format.time(minute, in: plan.timeZone))") {
            SkyView(plan: plan, scrubTime: .constant(minute), isPlaying: .constant(false),
                    planSegments: segments, showsControls: false, showsLabels: true)
                .padding(10)
                .background(Color.black.opacity(0.35))
                .allowsHitTesting(false)
        }
    }

    /// A titled box that takes half the width and all the height it's given.
    private func viewBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .kerning(0.7)
                .foregroundStyle(Self.accent)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Self.border))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countdown(to date: Date, from now: Date) -> String {
        Format.duration(minutes: max(1, date.timeIntervalSince(now) / 60))
    }

    // MARK: - Side

    private func sidePanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .kerning(0.7)
                .foregroundStyle(Self.accent)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Self.border))
    }

    /// The sky and the weather at this minute, and the one warning worth
    /// acting on tonight.
    private func conditions(now: Date) -> some View {
        let imperial = state.preferences.usesImperialUnits
        let tonight = plan.chartWindow.contains(now)
        let weather = tonight ? state.forecast.interpolated(at: now) : nil
        let session = TimeWindow(start: tonight ? now : plan.chartWindow.start, end: plan.chartWindow.end)
        let dew = plan.hasWeather ? DewRisk.assess(samples: plan.samples, over: session) : nil
        let moon = SkyCoordinates.horizontal(Moon.position(daysSinceJ2000: now.daysSinceJ2000).coordinate,
                                             daysSinceJ2000: now.daysSinceJ2000,
                                             latitude: plan.site.latitude, longitude: plan.site.longitude)
        let sun = Sun.altitude(daysSinceJ2000: now.daysSinceJ2000,
                               latitude: plan.site.latitude, longitude: plan.site.longitude)
        return sidePanel("Right now") {
            if let weather {
                conditionLine("Temperature", Format.temperature(celsius: weather.temperatureCelsius, imperial: imperial)
                              + " · dew point " + Format.temperature(celsius: weather.dewPointCelsius, imperial: imperial),
                              warn: weather.dewPointSpread < 2)
                conditionLine("Humidity", "\(Int(weather.relativeHumidity.rounded()))%",
                              warn: weather.relativeHumidity > 90)
                conditionLine("Wind", windText(weather, imperial: imperial),
                              warn: weather.windGustsKilometersPerHour > 30)
                conditionLine("Cloud", cloudText(weather),
                              warn: weather.effectiveCloudCover > state.preferences.maximumCloudCover)
                if weather.precipitationProbability >= 20 {
                    conditionLine("Rain chance", "\(Int(weather.precipitationProbability.rounded()))%", warn: true)
                }
            } else if !plan.hasWeather {
                Text("No forecast for this night.")
                    .foregroundStyle(Self.muted)
            }
            conditionLine("Sky", skyText(sunAltitude: sun), warn: false)
            conditionLine("Moon", moon.altitude > 0
                          ? "\(plan.moon.illuminationPercent)% lit · \(Format.degrees(moon.altitude)) up in the \(moon.compassPoint)"
                          : "\(plan.moon.illuminationPercent)% lit · below the horizon",
                          warn: false)
            if let dew, dew.level >= .high {
                conditionLine("Dew", "\(dew.level.name) from \(Format.time(dew.peakStart, in: plan.timeZone)) — heater recommended",
                              warn: true)
            }
            if let dawn = plan.astronomicalDawn, now < dawn {
                conditionLine("Dark until", "\(Format.time(dawn, in: plan.timeZone)) · \(Format.duration(minutes: dawn.timeIntervalSince(now) / 60)) left",
                              warn: false)
            }
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }

    private func windText(_ weather: HourlyWeather, imperial: Bool) -> String {
        var text = Format.wind(kilometersPerHour: weather.windSpeedKilometersPerHour, imperial: imperial)
        if let direction = weather.windDirectionDegrees {
            text = "\(HorizontalCoordinate(altitude: 0, azimuth: direction).compassPoint) " + text
        }
        return text + " · gusts " + Format.wind(kilometersPerHour: weather.windGustsKilometersPerHour, imperial: imperial)
    }

    private func cloudText(_ weather: HourlyWeather) -> String {
        "\(Int(weather.effectiveCloudCover.rounded()))% · low \(Int(weather.cloudCoverLow))%, mid \(Int(weather.cloudCoverMid))%, high \(Int(weather.cloudCoverHigh))%"
    }

    private func skyText(sunAltitude: Double) -> String {
        switch sunAltitude {
        case ..<(-18): return "Astronomical dark"
        case ..<(-12): return "Nautical twilight"
        case ..<(-6): return "Civil twilight"
        case ..<0: return "Twilight"
        default: return "Daylight"
        }
    }

    /// What's worth knowing about the target on now, or next.
    private func about(_ clock: SessionClock) -> some View {
        let block = clock.current ?? clock.next
        let designation = block.flatMap { b in plan.targets.first { $0.id == b.targetID }?.target.designation } ?? block?.targetID
        var facts = designation.map { CuratedFacts.facts(for: $0) } ?? []
        if facts.isEmpty, let designation, let fact = TargetFactCatalog.fact(for: designation) {
            facts = [fact]
        }
        return sidePanel(block.map { "About \($0.targetName)" } ?? "About") {
            if facts.isEmpty {
                Text("Nothing more on record for this one.")
                    .foregroundStyle(Self.muted)
            } else {
                ForEach(facts, id: \.self) { fact in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(Self.accent)
                        Text(fact).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }

    private func conditionLine(_ label: String, _ value: String, warn: Bool) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(Self.muted)
            Spacer(minLength: 10)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(warn ? Self.warning : Self.text)
        }
    }

    private func upNext(_ clock: SessionClock, now: Date) -> some View {
        // When the main panel is already showing the next block, list what
        // comes after it.
        let list = clock.phase == .running ? clock.upcoming : Array(clock.upcoming.dropFirst())
        return sidePanel("After that") {
            if list.isEmpty {
                Text("Nothing more planned.")
                    .foregroundStyle(Self.muted)
            } else {
                ForEach(list) { block in
                    HStack(spacing: 10) {
                        if let targetPlan = plan.targets.first(where: { $0.id == block.targetID }) {
                            ScoreBadge(score: targetPlan.score, size: 30)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.targetName).fontWeight(.semibold)
                            Text("\(Format.time(block.window.start, in: plan.timeZone))–\(Format.time(block.window.end, in: plan.timeZone)) · \(Format.duration(minutes: block.window.durationMinutes))")
                                .monospacedDigit()
                                .foregroundStyle(Self.muted)
                        }
                    }
                }
            }
            tonightSummary(now: now)
                .padding(.top, 4)
        }
        .font(.scaled(.callout, scale: uiTextScale))
    }

    @ViewBuilder
    private func tonightSummary(now: Date) -> some View {
        let first = segments.first?.window.start
        let last = segments.last?.window.end
        Divider().overlay(Self.border)
        VStack(alignment: .leading, spacing: 2) {
            Text("TONIGHT")
                .font(.scaled(.caption, scale: uiTextScale).weight(.semibold))
                .kerning(0.7)
                .foregroundStyle(Self.accent)
            Text("\(segments.count) block\(segments.count == 1 ? "" : "s")\(first.flatMap { f in last.map { " · \(Format.time(f, in: plan.timeZone))–\(Format.time($0, in: plan.timeZone))" } } ?? "")")
            if let last, now < last {
                Text("\(Format.duration(minutes: last.timeIntervalSince(max(now, first ?? now)) / 60)) of imaging left")
                    .foregroundStyle(Self.muted)
            }
        }
    }
}

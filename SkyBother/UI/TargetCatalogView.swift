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
    @State private var searchText = ""
    @State private var typeFilter: Set<TargetType> = []
    @State private var selected: Target?
    @State private var editorContext: CustomTargetEditorContext?
    @State private var sortOption: CatalogSortOption = .alphabetical

    private var customTargetIDs: Set<String> {
        Set(state.customTargets.map(\.id))
    }

    private var targets: [Target] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = BuiltInCatalog.all + state.customTargets
        let filtered = all.filter { target in
            if !typeFilter.isEmpty && !typeFilter.contains(target.type) { return false }
            if !query.isEmpty && !target.searchText.contains(query) { return false }
            return true
        }
        switch sortOption {
        case .alphabetical:
            return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .size:
            return filtered.sorted { $0.majorAxisArcminutes > $1.majorAxisArcminutes }
        case .brightness:
            return filtered.sorted { $0.magnitude < $1.magnitude }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(targets) { target in
                        let isCustom = customTargetIDs.contains(target.id)
                        TargetCatalogCell(target: target, isCustom: isCustom)
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
            TargetCatalogDetail(target: target)
        }
        .sheet(item: $editorContext) { context in
            CustomTargetEditor(existing: context.existing)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search the catalog", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.panelBorder))
            .frame(maxWidth: 280)

            Menu {
                Button("All Types") { typeFilter.removeAll() }
                Divider()
                ForEach(TargetType.allCases) { type in
                    Toggle(type.displayName, isOn: Binding(
                        get: { typeFilter.contains(type) },
                        set: { isOn in
                            if isOn { typeFilter.insert(type) } else { typeFilter.remove(type) }
                        }))
                }
            } label: {
                Label(typeFilter.isEmpty ? "All Types" : "\(typeFilter.count) Types",
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(CatalogSortOption.allCases) { option in
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

            Text("\(targets.count) targets")
                .font(.scaled(.callout, scale: uiTextScale))
                .foregroundStyle(.secondary)

            Button {
                editorContext = CustomTargetEditorContext(existing: nil)
            } label: {
                Label("Add Custom Target", systemImage: "plus.circle.fill")
            }
            .help("Add a target of your own — anything the built-in catalog doesn't cover")
        }
        .padding(16)
    }
}

/// Identifies one presentation of the custom-target editor sheet — `nil`
/// existing means "adding new," a value means "editing that target." Wrapped
/// in its own `Identifiable` rather than using `Target?` directly as the
/// `sheet(item:)` driver, since `nil` there would mean "no sheet" instead of
/// "new target."
private enum CatalogSortOption: String, CaseIterable, Identifiable {
    case alphabetical = "Alphabetical"
    case size = "Size in the Sky"
    case brightness = "Brightness"

    var id: String { rawValue }
}

private struct CustomTargetEditorContext: Identifiable {
    let id = UUID()
    var existing: Target?
}

private struct TargetCatalogCell: View {
    @Environment(\.uiTextScale) private var uiTextScale
    var target: Target
    var isCustom: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TargetThumbnail(designation: target.designation)
                .frame(height: 140)
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
                Text("\(target.designation) · \(target.constellation)")
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .panelStyle(cornerRadius: 12)
        .contentShape(Rectangle())
    }
}

struct TargetCatalogDetail: View {
    @Environment(\.uiTextScale) private var uiTextScale
    @Environment(\.dismiss) private var dismiss
    var target: Target

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.scaled(.title2, scale: uiTextScale).weight(.semibold))
                    Text("\(target.designation) · \(target.type.displayName) in \(target.constellation)")
                        .font(.scaled(.callout, scale: uiTextScale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .padding(.bottom, 0)

            // No ScrollView, no fixed height: fact text length varies a lot
            // (many targets have none at all, some have a full paragraph),
            // and the fetch script already caps a fact at 320 characters, so
            // the tallest this content ever gets is bounded. Letting the
            // VStack's own intrinsic size drive the sheet means it's exactly
            // as tall as this particular target needs, never more.
            VStack(alignment: .leading, spacing: 16) {
                TargetThumbnail(designation: target.designation, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(Palette.spaceTop, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.panelBorder))

                VStack(alignment: .leading, spacing: 8) {
                    factRow("Magnitude", String(format: "%.1f", target.magnitude))
                    factRow("Apparent size", target.sizeSummary)
                    factRow("Coordinates", Format.coordinates(target.coordinate))
                    if !target.type.isStarField {
                        factRow("Surface brightness", String(format: "%.1f mag/arcsec²", target.surfaceBrightness))
                    }
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

                if let info = TargetImageCatalog.info(for: target.designation), let url = URL(string: info.sourceURL) {
                    Link(destination: url) {
                        Label("Photo: \(info.sourceTitle) via Wikipedia", systemImage: "link")
                    }
                    .font(.scaled(.caption, scale: uiTextScale))
                    .foregroundStyle(Palette.accent)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 440, idealWidth: 460, maxWidth: 520)
        .spaceBackground()
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

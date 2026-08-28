import SwiftUI

/// A browsable reference catalog — every northern-hemisphere-reachable target
/// in the built-in list, with a photo, so you know what you're actually
/// pointing at before you commit a night to it. Independent of any night's
/// plan: this is "what's out there", not "what's up tonight".
struct TargetCatalogView: View {
    @State private var searchText = ""
    @State private var typeFilter: Set<TargetType> = []
    @State private var selected: Target?

    /// Targets that can plausibly rise for a northern-hemisphere observer.
    /// Excludes the handful of deep-southern showpieces (Magellanic Clouds,
    /// 47 Tucanae, Carina Nebula) that never clear the horizon north of the
    /// tropics.
    private static let northernReachable = BuiltInCatalog.all
        .filter { $0.declination > -55 }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

    private var targets: [Target] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.northernReachable.filter { target in
            if !typeFilter.isEmpty && !typeFilter.contains(target.type) { return false }
            if !query.isEmpty && !target.searchText.contains(query) { return false }
            return true
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
                        TargetCatalogCell(target: target)
                            .onTapGesture { selected = target }
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
                Button("All types") { typeFilter.removeAll() }
                Divider()
                ForEach(TargetType.allCases) { type in
                    Toggle(type.displayName, isOn: Binding(
                        get: { typeFilter.contains(type) },
                        set: { isOn in
                            if isOn { typeFilter.insert(type) } else { typeFilter.remove(type) }
                        }))
                }
            } label: {
                Label(typeFilter.isEmpty ? "All types" : "\(typeFilter.count) types",
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Text("\(targets.count) targets")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

private struct TargetCatalogCell: View {
    var target: Target

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TargetThumbnail(designation: target.designation)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.panelBorder))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: target.type.symbolName)
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                    Text(target.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(target.designation) · \(target.constellation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .panelStyle(cornerRadius: 12)
        .contentShape(Rectangle())
    }
}

private struct TargetCatalogDetail: View {
    @Environment(\.dismiss) private var dismiss
    var target: Target

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.title2.weight(.semibold))
                    Text("\(target.designation) · \(target.type.displayName) in \(target.constellation)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

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

            if let info = TargetImageCatalog.info(for: target.designation), let url = URL(string: info.sourceURL) {
                Link(destination: url) {
                    Label("Photo: \(info.sourceTitle) via Wikipedia", systemImage: "link")
                }
                .font(.caption)
                .foregroundStyle(Palette.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 440, height: 560)
        .spaceBackground()
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }
}

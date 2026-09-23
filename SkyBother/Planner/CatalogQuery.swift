import Foundation

/// How the Target Catalog narrows and orders itself against one night. Kept
/// out of the view so the rules can be tested, and so the catalog reads the
/// night's existing scores rather than working any out itself.
struct CatalogQuery: Equatable {
    enum Sort: String, CaseIterable, Identifiable {
        case alphabetical = "Alphabetical"
        case bestOnNight = "Best on This Night"
        case longestWindow = "Longest Window"
        case size = "Size in the Sky"
        case brightness = "Brightness"

        var id: String { rawValue }
        /// Orders that mean nothing without a night to score against.
        var needsNight: Bool { self == .bestOnNight || self == .longestWindow }
    }

    var search = ""
    var types: Set<TargetType> = []
    var sort: Sort = .alphabetical
    /// Good, Excellent or Exceptional on the night.
    var goodOnly = false
    /// Fits inside the frame without being lost in it — the same test as the
    /// planner's "Fits my frame".
    var fitsFrameOnly = false
    var minimumUsableHours: Double = 0

    /// True when any filter needs the night's scores.
    var filtersByNight: Bool { goodOnly || fitsFrameOnly || minimumUsableHours > 0 }

    static func fitsFrame(_ targetPlan: TargetPlan) -> Bool {
        !targetPlan.fit.needsMosaic && targetPlan.fit.fillFraction >= 0.10
    }

    /// `scored` is the night's own results, by target id. A target missing
    /// from it has no usable time that night; night filters drop it, and
    /// night sorts put it after every target that has some.
    func apply(to targets: [Target], scored: [String: TargetPlan]) -> [Target] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = targets.filter { target in
            if !types.isEmpty && !types.contains(target.type) { return false }
            if !query.isEmpty && !target.searchText.contains(query) { return false }
            guard filtersByNight else { return true }
            guard let result = scored[target.id] else { return false }
            if goodOnly && ![.exceptional, .excellent, .good].contains(result.verdict) { return false }
            if fitsFrameOnly && !Self.fitsFrame(result) { return false }
            if minimumUsableHours > 0 && result.usableMinutes < minimumUsableHours * 60 { return false }
            return true
        }

        func byName(_ a: Target, _ b: Target) -> Bool {
            a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        switch sort {
        case .alphabetical:
            return filtered.sorted(by: byName)
        case .size:
            return filtered.sorted { $0.majorAxisArcminutes > $1.majorAxisArcminutes }
        case .brightness:
            return filtered.sorted { $0.magnitude < $1.magnitude }
        case .bestOnNight, .longestWindow:
            let key: (TargetPlan) -> Double = sort == .bestOnNight ? { $0.score } : { $0.usableMinutes }
            return filtered.sorted { a, b in
                switch (scored[a.id], scored[b.id]) {
                case let (x?, y?): return key(x) != key(y) ? key(x) > key(y) : byName(a, b)
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return byName(a, b)
                }
            }
        }
    }
}

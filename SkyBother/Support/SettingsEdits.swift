import Foundation

/// Edits to settings as plain changes to a value, shared by the app
/// (AppState, which then refreshes or replans) and Settings' draft
/// (SettingsDraft, which keeps them until Save).
extension StoredSettings {
    mutating func apply(_ result: GeocodingResult) {
        let previousHorizon = hasSetLocation ? site.horizonAltitude : Site.unset.horizonAltitude
        // Keep the id stable if this is the same place, so saved sites do not
        // duplicate. With more than one spot saved at one address, though,
        // "the saved site near these coordinates" is ambiguous — a front yard
        // and a back yard are metres apart — so the one already in use wins.
        // Searching your own town again should leave you where you are rather
        // than silently move you to the other end of the house.
        let nearby = savedSites.filter {
            abs($0.latitude - result.latitude) < 0.01 && abs($0.longitude - result.longitude) < 0.01
        }
        let existing = nearby.first { $0.id == site.id } ?? nearby.first
        // A genuinely new site gets a first guess at its Bortle class from
        // the geocoder's population figure, rather than silently inheriting
        // whatever the previous site happened to be set to — population is a
        // loose proxy for light pollution, but it is better than a copy-paste
        // default the user has to remember to change. Re-picking a place
        // that is already saved keeps whatever Bortle class was set for it.
        let bortle = existing?.bortleClass
            ?? result.estimatedBortleClass
            ?? (hasSetLocation ? site.bortleClass : Site.unset.bortleClass)
        var newSite = result.makeSite(bortleClass: bortle, horizonAltitude: previousHorizon)
        if let existing {
            newSite.id = existing.id
            // Re-picking a place you already have keeps what you told the app
            // about it — its name and its horizon, profile and all — rather
            // than resetting them from the geocoder and the baseline of
            // wherever you happened to be standing. That mattered little when
            // a horizon was one number; it matters a lot once it is eight and
            // named "Back yard".
            newSite.name = existing.name
            newSite.horizonAltitude = existing.horizonAltitude
            newSite.horizonProfile = existing.horizonProfile
        }
        site = newSite
        hasSetLocation = true
        if !savedSites.contains(where: { $0.id == newSite.id }) {
            savedSites.append(newSite)
        }
    }

    /// Switches to a saved site, writing the outgoing one back first.
    ///
    /// That write-back is the whole point. A site is only ever saved when you
    /// leave it, so the copy in the list lags whatever you have been editing;
    /// switching away without saving first is exactly the moment those edits
    /// would be lost, and coming back via Use would quietly restore an older
    /// version of the site as though nothing had happened.
    mutating func switchToSavedSite(_ saved: Site) {
        var updated = self
        if let index = updated.savedSites.firstIndex(where: { $0.id == site.id }) {
            updated.savedSites[index] = site
        } else if hasSetLocation {
            updated.savedSites.append(site)
        }
        updated.site = saved
        self = updated

    }

    /// Saves the current site a second time as an independent entry at the
    /// same place. The front yard and the back yard share coordinates, weather,
    /// elevation and Bortle class, and differ only in what is in the way — so
    /// the copy takes all of that and gets its own horizon.
    ///
    /// The copy becomes the site in use, because the name field and the horizon
    /// sliders are directly above the button that makes it: the next thing you
    /// want to do is describe the spot you just created, not hunt for it in the
    /// list below.
    mutating func duplicateCurrentSite() {
        var updated = self
        // The original may never have been saved (nothing saves a site until
        // you switch away from it), and may hold edits newer than its saved
        // copy, so it is written back first.
        if let index = updated.savedSites.firstIndex(where: { $0.id == site.id }) {
            updated.savedSites[index] = site
        } else {
            updated.savedSites.append(site)
        }

        // Named only now, against the list *after* that write-back. Taking the
        // names beforehand meant checking against a stale one — a site renamed
        // "Back yard" still listed under the town it was found in — so the
        // copy saw no collision and came out sharing its original's name,
        // which is precisely the confusion the unique name exists to avoid.
        var copy = site
        copy.id = UUID()
        copy.name = Site.uniqueName(basedOn: site.name, avoiding: updated.savedSites.map(\.name))
        updated.savedSites.append(copy)
        updated.site = copy
        updated.hasSetLocation = true
        self = updated

    }

    mutating func removeSite(_ target: Site) {
        savedSites.removeAll { $0.id == target.id }
    }

    mutating func applyPreset(_ preset: Rig) {
        var copy = preset
        copy.id = UUID()
        rig = copy
    }

    /// Keeps the current rig in the saved list so you can switch between several
    /// instruments without re-typing their numbers.
    mutating func saveCurrentRig() {
        if let match = savedRigMatchingCurrent, let index = savedRigs.firstIndex(where: { $0.id == match.id }) {
            var updated = rig
            updated.id = match.id
            savedRigs[index] = updated
        } else {
            savedRigs.append(rig)
        }
    }

    /// Keeps the current numbers as a new saved rig, leaving any rig they
    /// started from untouched.
    mutating func saveCurrentRigAsNew() {
        var copy = rig
        copy.id = UUID()
        let names = savedRigs.map(\.name)
        if names.contains(copy.name) {
            var n = 2
            while names.contains("\(rig.name) \(n)") { n += 1 }
            copy.name = "\(rig.name) \(n)"
        }
        savedRigs.append(copy)
        rig = copy
    }

    /// True when the active rig is exactly one of the built-in presets.
    var rigIsUnchangedPreset: Bool {
        Rig.presets.contains { preset in
            var candidate = rig
            candidate.id = preset.id
            return candidate == preset
        }
    }

    mutating func removeRig(_ target: Rig) {
        savedRigs.removeAll { $0.id == target.id }
    }

    var isCurrentRigSaved: Bool { savedRigMatchingCurrent != nil }

    /// Whether a saved rig is the one in use: the same rig, or a copy of it —
    /// a preset loaded again is a fresh rig with the same name and numbers,
    /// and calling its saved twin "not in use" offered to save it twice.
    func isInUse(_ saved: Rig) -> Bool {
        saved.id == rig.id || (saved.name == rig.name && saved.hasSameSpecs(as: rig))
    }

    var savedRigMatchingCurrent: Rig? {
        savedRigs.first { $0.id == rig.id } ?? savedRigs.first(where: isInUse)
    }
}

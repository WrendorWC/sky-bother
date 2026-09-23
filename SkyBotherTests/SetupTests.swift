import XCTest

/// Guided setup's saved progress, goal presets and rig checks.
final class SetupTests: XCTestCase {

    // MARK: - Saved progress

    /// A settings file from before guided setup existed has a site but no
    /// setup step: it must decode as already set up, not send an existing
    /// user back through setup on upgrade.
    func testSettingsWrittenBeforeGuidedSetupCountAsDone() throws {
        var settings = StoredSettings.initial
        settings.site = Site(name: "Back Yard", latitude: 28.2, longitude: -82.3, elevationMeters: 20,
                             timeZoneIdentifier: "America/New_York", bortleClass: 7,
                             horizonAltitude: 20, horizonProfile: nil)
        settings.hasSetLocation = true
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "setupStep")
        let old = try JSONSerialization.data(withJSONObject: json)

        let loaded = try JSONDecoder().decode(StoredSettings.self, from: old)
        XCTAssertTrue(loaded.hasSetLocation)
        XCTAssertNil(loaded.setupStep)
    }

    func testSetupProgressSurvivesARelaunch() throws {
        var settings = StoredSettings.initial
        settings.setupStep = 3
        let loaded = try JSONDecoder().decode(StoredSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(loaded.setupStep, 3)
    }

    // MARK: - Goal presets

    func testEachPresetIsRecognisedFromTheValuesItSets() {
        for preset in GoalPreset.allCases where preset != .custom {
            var preferences = Preferences.default
            preset.apply(to: &preferences)
            XCTAssertEqual(GoalPreset.matching(preferences), preset)
        }
    }

    func testChangingAValueAfterAPresetMakesItCustomAndKeepsTheValues() {
        var preferences = Preferences.default
        GoalPreset.deepIntegration.apply(to: &preferences)
        preferences.integrationGoalMinutes = 255
        XCTAssertEqual(GoalPreset.matching(preferences), .custom)
        XCTAssertEqual(preferences.integrationGoalMinutes, 255)
        XCTAssertEqual(preferences.planEmphasis, .longerIntegration)
    }

    func testApplyingCustomChangesNothing() {
        var preferences = Preferences.default
        preferences.integrationGoalMinutes = 95
        GoalPreset.custom.apply(to: &preferences)
        XCTAssertEqual(preferences.integrationGoalMinutes, 95)
    }

    // MARK: - Rigs

    func testEveryPresetPassesTheRigChecks() {
        for preset in Rig.presets {
            XCTAssertEqual(preset.validationProblems, [], preset.name)
        }
    }

    func testImpossibleNumbersAreCaught() {
        var rig = Rig.seestarS50
        rig.focalLengthMillimeters = 0
        rig.pixelSizeMicrons = -1
        XCTAssertEqual(rig.validationProblems.count, 2)

        var slow = Rig.seestarS50
        slow.focalLengthMillimeters = slow.apertureMillimeters * 80
        XCTAssertTrue(slow.validationProblems.contains { $0.contains("outside what real optics use") })
    }

    func testSmartTelescopesAreGroupedApart() {
        XCTAssertEqual(Rig.seestarS50.presetGroup, .smartTelescope)
        XCTAssertEqual(Rig.dwarf3.presetGroup, .smartTelescope)
        XCTAssertEqual(Rig.refractor80.presetGroup, .cameraAndOptics)
    }
}

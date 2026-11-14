// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import TOML
import XCTest

final class ForkSchemaSixMigrationTests: XCTestCase {
    func testUpstreamAndForkSchemasMigrateWithoutLosingFocusOrResizeBindings() throws {
        XCTAssertEqual(SettingsTOMLCodec.currentSchemaVersion, 6)
        for version in [3, 4, 5] {
            for mode: MonitorCrossingFocus? in [nil, .spatial, .lastFocused] {
                for legacyHotkeys in [false, true] {
                    var expected = SettingsExport.defaults()
                    expected.focus.monitorCrossingFocus = mode ?? .spatial
                    let original = try legacyData(version: version, mode: mode, legacyHotkeys: legacyHotkeys)
                    let result = try SettingsTOMLCodec.decodeForLoad(original)
                    let report = try XCTUnwrap(result.migration)
                    XCTAssertEqual(report.fromVersion, version)
                    XCTAssertEqual(report.toVersion, 6)
                    XCTAssertEqual(report.defaultedPaths, mode == nil ? ["focus.monitorCrossingFocus"] : [])
                    XCTAssertEqual(report.mappedHotkeys.count, legacyHotkeys ? resizeMappings.count : 0)
                    XCTAssertEqual(result.export, expected)
                    let migrated = try XCTUnwrap(result.migratedData)
                    XCTAssertTrue(SettingsTOMLCodec.unknownKeyPaths(in: migrated).contains("futureExtension"))
                    let tree = try TOMLDecoder().decode([String: TOMLNode].self, from: migrated)
                    XCTAssertEqual(tree["futureExtension"], .table(["value": .string("preserve")]))
                    let reloaded = try SettingsTOMLCodec.decodeForLoad(migrated)
                    XCTAssertEqual(reloaded.export, expected)
                    XCTAssertNil(reloaded.migration)
                    XCTAssertNil(reloaded.migratedData)
                }
            }
        }
    }

    func testForkSchemaFivePreservesExplicitCurrentResizeBindingOverLegacyAlias() throws {
        let original = try legacyData(version: 5, mode: .lastFocused, legacyHotkeys: false)
        let alias = "\n[[hotkeys]]\nid = \"setContainerPrimarySpan.decrease10Percent\"\nbinding = \"Option+L\"\n"
        let result = try SettingsTOMLCodec.decodeForLoad(original + Data(alias.utf8))
        XCTAssertEqual(result.export.hotkeyBindings, SettingsExport.defaults().hotkeyBindings)
        XCTAssertEqual(result.migration?.mappedHotkeys, [SettingsHotkeyMapping(
            previousID: "setContainerPrimarySpan.decrease10Percent",
            currentID: "resizeContainerPrimarySpan.shrink",
            keptExplicitCurrentBinding: true
        )])
    }

    func testSchemaFiveRejectsInvalidFocusAndDiscardedResizeAliases() throws {
        let source = String(
            decoding: try legacyData(version: 5, mode: .lastFocused, legacyHotkeys: false),
            as: UTF8.self
        )
        let invalidFocus = source.replacingOccurrences(
            of: "monitorCrossingFocus = \"last\"",
            with: "monitorCrossingFocus = \"invalid\""
        )
        XCTAssertNotEqual(source, invalidFocus)
        XCTAssertThrowsError(try SettingsTOMLCodec.decodeForLoad(Data(invalidFocus.utf8)))
        for binding in ["\"NotAKey\"", "17"] {
            let alias = "\n[[hotkeys]]\nid = \"setContainerPrimarySpan.decrease10Percent\"\nbinding = \(binding)\n"
            XCTAssertThrowsError(try SettingsTOMLCodec.decodeForLoad(Data((source + alias).utf8)))
        }
    }

    @MainActor
    func testSchemaFiveStartupBacksUpBytesAndPreservesOlderBackupSlots() throws {
        for mode: MonitorCrossingFocus? in [nil, .lastFocused] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let original = try legacyData(version: 5, mode: mode, legacyHotkeys: mode != nil)
            let settings = root.appendingPathComponent(SettingsFilePersistence.fileName)
            try original.write(to: settings)
            let olderBackup = root.appendingPathComponent(SettingsFilePersistence.migrationBackupFileNames(for: 5)[0])
            let olderData = Data("existing schema-four backup".utf8)
            try olderData.write(to: olderBackup)
            let persistence = SettingsFilePersistence(directory: root, startWatching: false, deferSaves: false)
            let outcome = persistence.loadOutcome()
            guard let notice = outcome.notice, case let .migrated(report, backup) = notice else {
                return XCTFail("Expected schema-five migration")
            }
            XCTAssertEqual(report.fromVersion, 5)
            XCTAssertEqual(report.toVersion, 6)
            XCTAssertEqual(try Data(contentsOf: backup), original)
            XCTAssertEqual(try Data(contentsOf: olderBackup), olderData)
            let rewritten = try Data(contentsOf: settings)
            XCTAssertEqual(try SettingsTOMLCodec.decode(rewritten), outcome.export)
            XCTAssertEqual(outcome.export?.focus.monitorCrossingFocus, mode ?? .spatial)
            let reloaded = persistence.loadOutcome()
            XCTAssertNil(reloaded.notice)
            XCTAssertEqual(reloaded.export, outcome.export)
            XCTAssertEqual(try Data(contentsOf: settings), rewritten)
        }
    }

    func testMonitorCrossingModesRoundTripInCurrentSchema() throws {
        for mode in MonitorCrossingFocus.allCases {
            var export = SettingsExport.defaults()
            export.focus.monitorCrossingFocus = mode
            let data = try SettingsTOMLCodec.encode(export)
            XCTAssertEqual(try SettingsTOMLCodec.decode(data), export)
            XCTAssertFalse(SettingsTOMLCodec.unknownKeyPaths(in: data).contains("focus.monitorCrossingFocus"))
        }
    }

    private let resizeMappings = [
        ("setContainerPrimarySpan.decrease10Percent", "resizeContainerPrimarySpan.shrink"),
        ("setContainerPrimarySpan.increase10Percent", "resizeContainerPrimarySpan.grow"),
        ("setWindowPrimarySpan.decrease10Percent", "resizeWindowPrimarySpan.shrink"),
        ("setWindowPrimarySpan.increase10Percent", "resizeWindowPrimarySpan.grow"),
        ("setWindowSecondarySpan.decrease10Percent", "resizeWindowSecondarySpan.shrink"),
        ("setWindowSecondarySpan.increase10Percent", "resizeWindowSecondarySpan.grow")
    ]

    private func legacyData(version: Int, mode: MonitorCrossingFocus?, legacyHotkeys: Bool) throws -> Data {
        var export = SettingsExport.defaults()
        export.focus.monitorCrossingFocus = mode ?? .spatial
        var text = String(decoding: try SettingsTOMLCodec.encode(export), as: UTF8.self)
            .replacingOccurrences(of: "schemaVersion = 6", with: "schemaVersion = \(version)")
        if mode == nil {
            text = text.replacingOccurrences(of: "monitorCrossingFocus = \"spatial\"\n", with: "")
        }
        if legacyHotkeys {
            for (previous, current) in resizeMappings {
                text = text.replacingOccurrences(of: "\"\(current)\"", with: "\"\(previous)\"")
            }
        }
        return Data((text + "\n[futureExtension]\nvalue = \"preserve\"\n").utf8)
    }
}

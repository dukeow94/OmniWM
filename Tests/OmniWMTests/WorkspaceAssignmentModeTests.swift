// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
@testable import OmniWMCtl
import OmniWMIPC
import XCTest

@MainActor
final class WorkspaceAssignmentModeTests: XCTestCase {
    func testLegacyRulesDefaultToFirstWindowWithoutAddingPersistedKey() throws {
        let data = Data(#"{"bundleId":"com.google.Chrome","assignToWorkspace":"9"}"#.utf8)
        let rule = try JSONDecoder().decode(AppRule.self, from: data)
        XCTAssertNil(rule.workspaceAssignmentMode)
        XCTAssertEqual(rule.effectiveWorkspaceAssignmentMode, .firstWindow)
        XCTAssertEqual(AppRuleDraft(rule: rule).workspaceAssignmentMode, .firstWindow)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any]
        )
        XCTAssertNil(object["workspaceAssignmentMode"])

        let definition = try JSONDecoder().decode(
            IPCRuleDefinition.self,
            from: Data(#"{"bundleId":"com.google.Chrome","layout":"float","assignToWorkspace":"9"}"#.utf8)
        )
        XCTAssertNil(definition.workspaceAssignmentMode)
        XCTAssertEqual(IPCRuleProjection.appRule(from: definition).effectiveWorkspaceAssignmentMode, .firstWindow)

        let snapshot = try JSONDecoder().decode(
            IPCRuleSnapshot.self,
            from: Data(
                #"{"id":"x","position":1,"bundleId":"com.google.Chrome","layout":"float","specificity":2,"isValid":true}"#
                    .utf8
            )
        )
        XCTAssertNil(snapshot.workspaceAssignmentMode)
    }

    func testModesRoundTripThroughTOMLAndIPC() throws {
        for mode in WindowRuleWorkspaceAssignmentMode.allCases {
            let rule = AppRule(
                bundleId: "com.google.Chrome", layout: .float,
                assignToWorkspace: "9", workspaceAssignmentMode: mode
            )
            var export = SettingsExport.defaults()
            export.appRules = [rule]
            let toml = try SettingsTOMLCodec.encode(export)
            XCTAssertEqual(try SettingsTOMLCodec.decode(toml).appRules, [rule])
            XCTAssertTrue(SettingsTOMLCodec.unknownKeyPaths(in: toml).isEmpty)

            let definition = IPCRuleProjection.definition(from: rule)
            let definitionData = try JSONEncoder().encode(definition)
            let decoded = try JSONDecoder().decode(IPCRuleDefinition.self, from: definitionData)
            XCTAssertEqual(IPCRuleProjection.appRule(from: decoded, id: rule.id), rule)

            let snapshot = IPCRuleProjection.snapshot(from: rule, position: 1, invalidRegexMessagesByRuleId: [:])
            XCTAssertEqual(snapshot.workspaceAssignmentMode?.rawValue, mode.rawValue)
            XCTAssertTrue(snapshot.isValid)
            XCTAssertEqual(
                try JSONDecoder().decode(IPCRuleSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot
            )
            let request = IPCRequest(id: "assignment-mode", rule: .add(rule: definition))
            XCTAssertEqual(try IPCWire.decodeRequest(from: IPCWire.encodeRequestLine(request)), request)
            let response = IPCResponse.success(
                id: "assignment-mode", kind: .query,
                result: IPCResult(rules: IPCRulesQueryResult(rules: [snapshot]))
            )
            XCTAssertEqual(try IPCWire.decodeResponse(from: IPCWire.encodeResponseLine(response)), response)
        }
    }

    func testDraftTracksModeChangesAndClearsModeWhenAssignmentIsDisabled() {
        let rule = AppRule(bundleId: "com.google.Chrome", layout: .float, assignToWorkspace: "9")
        var draft = AppRuleDraft(rule: rule)
        let original = draft
        draft.workspaceAssignmentMode = .allNewWindows
        XCTAssertNotEqual(draft, original)
        XCTAssertFalse(draft.represents(rule))
        XCTAssertEqual(draft.makeRule().workspaceAssignmentMode, .allNewWindows)
        XCTAssertEqual(AppRuleDraft(rule: draft.makeRule()), draft)

        draft.assignToWorkspaceEnabled = false
        XCTAssertNil(draft.makeRule().assignToWorkspace)
        XCTAssertNil(draft.makeRule().workspaceAssignmentMode)
    }

    func testModeAloneDoesNotCountAsAnEffect() {
        let rule = AppRule(bundleId: "com.google.Chrome", workspaceAssignmentMode: .allNewWindows)
        XCTAssertFalse(rule.hasEffect)
        XCTAssertFalse(IPCRuleValidator.validate(IPCRuleProjection.definition(from: rule)).isValid)
    }

    func testCLIParsesModesForAddAndReplace() throws {
        let ruleId = UUID().uuidString
        for action in [["add"], ["replace", ruleId]] {
            for (value, mode): (String, IPCRuleWorkspaceAssignmentMode) in [
                ("first-window", .firstWindow), ("all-new-windows", .allNewWindows)
            ] {
                let parsed = try CLIParser.parse(arguments: ["omniwmctl", "rule"] + action + [
                    "--bundle-id", "com.google.Chrome", "--assign-to-workspace", "9",
                    "--workspace-assignment-mode", value
                ])
                guard case let .rule(request) = parsed.request.payload else {
                    return XCTFail("Expected a rule request")
                }
                let definition: IPCRuleDefinition
                switch request {
                case let .add(rule),
                     let .replace(_, rule): definition = rule
                default: return XCTFail("Expected add or replace")
                }
                XCTAssertEqual(definition.workspaceAssignmentMode, mode)
                XCTAssertEqual(definition.assignToWorkspace, "9")
            }
        }
    }

    func testCLIRejectsMissingInvalidAndDuplicateModeValues() {
        let prefix = ["omniwmctl", "rule", "add", "--bundle-id", "com.google.Chrome", "--assign-to-workspace", "9"]
        for arguments in [
            ["--workspace-assignment-mode"],
            ["--workspace-assignment-mode", "always"],
            ["--workspace-assignment-mode", "all-new-windows", "--workspace-assignment-mode", "first-window"]
        ] {
            XCTAssertThrowsError(try CLIParser.parse(arguments: prefix + arguments))
        }
    }

    func testCLIWithoutModePreservesLegacyDefault() throws {
        let parsed = try CLIParser.parse(arguments: [
            "omniwmctl", "rule", "add", "--bundle-id", "com.google.Chrome", "--assign-to-workspace", "9"
        ])
        guard case let .rule(.add(definition)) = parsed.request.payload else {
            return XCTFail("Expected add rule")
        }
        XCTAssertNil(definition.workspaceAssignmentMode)
    }

    func testRuleQueryRenderingIncludesAssignmentMode() {
        let snapshot = IPCRuleSnapshot(
            id: "x", position: 1, bundleId: "com.google.Chrome", layout: .float,
            assignToWorkspace: "9", workspaceAssignmentMode: .allNewWindows,
            specificity: 2, isValid: true
        )
        let output = CLIStateRenderer.formattedRules(IPCRulesQueryResult(rules: [snapshot]), format: .tsv)
        XCTAssertTrue(output.contains("WORKSPACE ASSIGNMENT"))
        XCTAssertTrue(output.contains("allNewWindows"))
    }
}

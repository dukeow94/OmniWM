// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/BarutSRB/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class MonitorCrossingFocusTests: XCTestCase {
    private struct FloatingFixture {
        let root: URL
        let controller: WMController
        let sourceMonitor: Monitor
        let targetMonitor: Monitor
        let targetWorkspaceId: WorkspaceDescriptor.ID
    }

    private func token(_ id: Int) -> WindowToken {
        WindowToken(pid: 1, windowId: id)
    }

    func testSpatialPolicySelectsSpatialNeighbor() {
        let spatial = token(1)
        let farther = token(2)
        let result = WorkspaceNavigationHandler.monitorCrossingFocusToken(
            policy: .spatial,
            from: CGRect(x: 0, y: 200, width: 400, height: 400),
            candidates: [
                (token: farther, frame: CGRect(x: 1_600, y: 0, width: 300, height: 800)),
                (token: spatial, frame: CGRect(x: 1_000, y: 200, width: 300, height: 400))
            ],
            direction: .right,
            targetFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(result, spatial)
    }

    func testLastPolicyDoesNotSelectOrReplaceSpatialNeighbor() {
        let spatial = token(3)
        let result = WorkspaceNavigationHandler.monitorCrossingFocusToken(
            policy: .last,
            from: CGRect(x: 0, y: 200, width: 400, height: 400),
            candidates: [(token: spatial, frame: CGRect(x: 1_000, y: 200, width: 300, height: 400))],
            direction: .right,
            targetFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800)
        )

        XCTAssertNil(result)
    }

    func testLastPolicyRestoresFloatingWorkspaceHistoryAcrossMonitorEdge() throws {
        let fixture = try makeFloatingFixture()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixture.root)
        }
        defer {
            fixture.controller.deadlineWheel.stop()
            fixture.controller.layoutRefreshController.resetState()
        }

        let manager = fixture.controller.workspaceManager
        let targetFirst = addFloatingWindow(
            pid: 1_004_010,
            windowId: 1,
            to: fixture.targetWorkspaceId,
            manager: manager
        )
        let targetLast = addFloatingWindow(
            pid: 1_004_010,
            windowId: 2,
            to: fixture.targetWorkspaceId,
            manager: manager
        )
        _ = manager.rememberFocus(targetFirst, in: fixture.targetWorkspaceId)
        _ = manager.rememberFocus(targetLast, in: fixture.targetWorkspaceId)

        XCTAssertTrue(fixture.controller.workspaceNavigationHandler.focusMonitor(direction: .right))
        XCTAssertEqual(manager.interactionMonitorId, fixture.targetMonitor.id)
        XCTAssertEqual(manager.resolveWorkspaceFocusToken(in: fixture.targetWorkspaceId), targetLast)
    }

    private func makeFloatingFixture() throws -> FloatingFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OmniWMMonitorCrossingFocusTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceMonitor = monitor(
            displayId: 1_004_001,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        let targetMonitor = monitor(
            displayId: 1_004_002,
            frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800)
        )
        let settings = makeSettings(root: root, source: sourceMonitor, target: targetMonitor)
        let controller = makeController(settings: settings)
        let manager = controller.workspaceManager
        manager.applyMonitorConfigurationChange([sourceMonitor, targetMonitor])
        manager.applySettings()
        let sourceWorkspaceId = try XCTUnwrap(manager.workspaceId(named: "1"))
        let targetWorkspaceId = try XCTUnwrap(manager.workspaceId(named: "2"))
        XCTAssertTrue(manager.setActiveWorkspace(sourceWorkspaceId, on: sourceMonitor.id))
        XCTAssertTrue(
            manager.setActiveWorkspace(
                targetWorkspaceId,
                on: targetMonitor.id,
                updateInteractionMonitor: false
            )
        )
        _ = manager.setInteractionMonitor(sourceMonitor.id)
        return FloatingFixture(
            root: root,
            controller: controller,
            sourceMonitor: sourceMonitor,
            targetMonitor: targetMonitor,
            targetWorkspaceId: targetWorkspaceId
        )
    }

    private func makeSettings(root: URL, source: Monitor, target: Monitor) -> SettingsStore {
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        settings.focus.crossesMonitorAtEdge = true
        settings.focus.monitorCrossingFocus = .last
        settings.workspaces.configurations = [
            WorkspaceConfiguration(
                name: "1",
                monitorAssignment: .specificDisplay(OutputId(from: source)),
                layoutType: .niri
            ),
            WorkspaceConfiguration(
                name: "2",
                monitorAssignment: .specificDisplay(OutputId(from: target)),
                layoutType: .niri
            )
        ]
        return settings
    }

    private func makeController(settings: SettingsStore) -> WMController {
        WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
    }

    private func monitor(displayId: CGDirectDisplayID, frame: CGRect) -> Monitor {
        Monitor(
            id: .init(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Monitor \(displayId)"
        )
    }

    private func addFloatingWindow(
        pid: pid_t,
        windowId: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        manager: WorkspaceManager
    ) -> WindowToken {
        manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId,
            mode: .floating
        )
    }
}

// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import QuartzCore
import Synchronization
import XCTest

@MainActor
final class NiriLayoutBuildMetricsRegressionTests: XCTestCase {
    private struct Fixture {
        let controller: WMController
        let engine: NiriLayoutEngine
        let monitor: Monitor
        let workspaceId: WorkspaceDescriptor.ID
        let token: WindowToken
    }

    func testScrollBuildMetricRecordsWhileDetailedTraceIsInactive() throws {
        ScrollTickTrace.shared.endCapture()
        let fixture = try makeFixture()

        XCTAssertFalse(ScrollTickTrace.shared.isActive)
        XCTAssertTrue(
            fixture.controller.layoutRefreshController.niriHandler.applyFramesOnDemand(
                wsId: fixture.workspaceId,
                state: fixture.controller.workspaceManager.niriViewportState(for: fixture.workspaceId),
                engine: fixture.engine,
                monitor: fixture.monitor,
                animationTime: CACurrentMediaTime()
            )
        )

        let dump = fixture.controller.layoutRefreshController.layoutBuildMetricsDump()
        XCTAssertTrue(dump.contains("builds=1"))
        XCTAssertTrue(dump.contains("route=scrollTick ws=1 win=1-2 n=1"))
    }

    func testSettleBuildMetricRecordsWithoutDetailedTraceEntry() throws {
        let fixture = try makeFixture()
        ScrollTickTrace.shared.beginCapture()
        defer { ScrollTickTrace.shared.endCapture() }

        XCTAssertTrue(
            fixture.controller.layoutRefreshController.niriHandler.applyFramesOnDemand(
                wsId: fixture.workspaceId,
                state: fixture.controller.workspaceManager.niriViewportState(for: fixture.workspaceId),
                engine: fixture.engine,
                monitor: fixture.monitor
            )
        )

        let dump = fixture.controller.layoutRefreshController.layoutBuildMetricsDump()
        XCTAssertTrue(dump.contains("builds=1"))
        XCTAssertTrue(dump.contains("route=scrollTick ws=1 win=1-2 n=1"))
        XCTAssertEqual(ScrollTickTrace.shared.dump(), "none")
    }

    func testAnimationBuildUsesPositionOnlyAXForTrustedSameSizeFrame() throws {
        let fixture = try makeFixture()
        let target = try addWindowAndTargetFrame(to: fixture)
        fixture.controller.axManager.confirmFrameWrite(
            for: fixture.token.windowId,
            frame: target.offsetBy(dx: -30, dy: 0)
        )

        XCTAssertTrue(
            fixture.controller.layoutRefreshController.niriHandler.applyFramesOnDemand(
                wsId: fixture.workspaceId,
                state: fixture.controller.workspaceManager.niriViewportState(for: fixture.workspaceId),
                engine: fixture.engine,
                monitor: fixture.monitor,
                animationTime: CACurrentMediaTime()
            )
        )

        XCTAssertEqual(
            fixture.controller.axManager.recentFrameWriteFailureComponents(for: fixture.token.windowId),
            .position
        )
    }

    func testAnimationBuildUsesPositionOnlyAXWhenWindowSizeRoundsByOnePoint() throws {
        let fixture = try makeFixture()
        let target = try addWindowAndTargetFrame(to: fixture)
        fixture.controller.axManager.confirmFrameWrite(
            for: fixture.token.windowId,
            frame: CGRect(
                x: target.minX - 30,
                y: target.minY,
                width: target.width + 1,
                height: target.height
            )
        )

        XCTAssertTrue(
            fixture.controller.layoutRefreshController.niriHandler.applyFramesOnDemand(
                wsId: fixture.workspaceId,
                state: fixture.controller.workspaceManager.niriViewportState(for: fixture.workspaceId),
                engine: fixture.engine,
                monitor: fixture.monitor,
                animationTime: CACurrentMediaTime()
            )
        )

        XCTAssertEqual(
            fixture.controller.axManager.recentFrameWriteFailureComponents(for: fixture.token.windowId),
            .position
        )
    }

    func testTerminalScrollTickBuildsOneFullFrameSettlementPlan() throws {
        let fixture = try makeFixture()
        let target = try addWindowAndTargetFrame(to: fixture)
        fixture.controller.axManager.confirmFrameWrite(
            for: fixture.token.windowId,
            frame: target.offsetBy(dx: -30, dy: 0)
        )
        ScrollTickTrace.shared.beginCapture()
        FrameApplyTrace.shared.beginCapture()
        defer {
            ScrollTickTrace.shared.endCapture()
            FrameApplyTrace.shared.endCapture()
        }

        XCTAssertTrue(
            fixture.controller.layoutRefreshController.niriHandler.registerScrollAnimation(
                fixture.workspaceId,
                on: fixture.monitor.displayId
            )
        )
        fixture.controller.layoutRefreshController.niriHandler.tickScrollAnimation(
            targetTime: CACurrentMediaTime(),
            displayId: fixture.monitor.displayId
        )

        XCTAssertNil(
            fixture.controller.layoutRefreshController.niriHandler
                .scrollAnimationByDisplay[fixture.monitor.displayId]
        )
        let dump = fixture.controller.layoutRefreshController.layoutBuildMetricsDump()
        XCTAssertTrue(dump.contains("builds=1"))
        XCTAssertTrue(dump.contains("route=scrollTick ws=1 win=1-2 n=1"))
        XCTAssertTrue(ScrollTickTrace.shared.dump().contains("anim=false"))
        let applications = FrameApplyTrace.shared.dump().split(separator: "\n").filter {
            $0.contains("win=\(fixture.token.windowId) ")
                && $0.contains("event=outcome=skip/contextUnavailable")
        }
        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(
            applications.filter { $0.contains("target=\(TraceFormat.rect(target))") }.count,
            1
        )
        XCTAssertEqual(
            fixture.controller.axManager.recentFrameWriteFailureComponents(for: fixture.token.windowId),
            .all
        )
    }

    func testOngoingScrollTickSubmitsOnePositionOnlyAnimationPlan() throws {
        let fixture = try makeFixture()
        let target = try addWindowAndTargetFrame(to: fixture)
        fixture.controller.axManager.confirmFrameWrite(
            for: fixture.token.windowId,
            frame: target.offsetBy(dx: -30, dy: 0)
        )
        let targetTime = CACurrentMediaTime()
        let animationDriver = fixture.controller.workspaceManager.animationDriver
        animationDriver.gestureLivenessNow = { targetTime }
        XCTAssertNotNil(
            animationDriver.beginGesture(
                in: fixture.workspaceId,
                isTrackpad: false,
                timestamp: targetTime
            )
        )
        XCTAssertTrue(
            animationDriver.hasMotion(in: fixture.workspaceId)
        )
        ScrollTickTrace.shared.beginCapture()
        FrameApplyTrace.shared.beginCapture()
        defer {
            ScrollTickTrace.shared.endCapture()
            FrameApplyTrace.shared.endCapture()
        }

        XCTAssertTrue(
            fixture.controller.layoutRefreshController.niriHandler.registerScrollAnimation(
                fixture.workspaceId,
                on: fixture.monitor.displayId
            )
        )
        fixture.controller.layoutRefreshController.niriHandler.tickScrollAnimation(
            targetTime: targetTime,
            displayId: fixture.monitor.displayId
        )

        XCTAssertEqual(
            fixture.controller.layoutRefreshController.niriHandler
                .scrollAnimationByDisplay[fixture.monitor.displayId],
            fixture.workspaceId
        )
        XCTAssertTrue(ScrollTickTrace.shared.dump().contains("anim=true"))
        let applications = FrameApplyTrace.shared.dump().split(separator: "\n").filter {
            $0.contains("win=\(fixture.token.windowId) ")
                && $0.contains("event=outcome=skip/contextUnavailable")
        }
        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(
            fixture.controller.axManager.recentFrameWriteFailureComponents(for: fixture.token.windowId),
            .position
        )
    }

    func testFocusProxyScrollTickUsesFinalVerifiedFrameInsteadOfIntermediateFrame() throws {
        let fixture = try makeFixture()
        let settledFrame = try addWindowAndTargetFrame(to: fixture)
        let proxyTarget = settledFrame.offsetBy(dx: 120, dy: 0)
        fixture.controller.axManager.confirmFrameWrite(
            for: fixture.token.windowId,
            frame: settledFrame.offsetBy(dx: -30, dy: 0)
        )
        fixture.controller.layoutRefreshController.focusScrollProxy.targetLayoutForTests = .init(
            workspaceId: fixture.workspaceId,
            frames: [fixture.token: proxyTarget],
            hiddenHandles: [:]
        )
        let targetTime = CACurrentMediaTime()
        let animationDriver = fixture.controller.workspaceManager.animationDriver
        animationDriver.gestureLivenessNow = { targetTime }
        XCTAssertNotNil(animationDriver.beginGesture(in: fixture.workspaceId, isTrackpad: false, timestamp: targetTime))
        ScrollTickTrace.shared.beginCapture()
        FrameApplyTrace.shared.beginCapture()
        defer {
            ScrollTickTrace.shared.endCapture()
            FrameApplyTrace.shared.endCapture()
        }

        XCTAssertTrue(fixture.controller.layoutRefreshController.niriHandler.applyFramesOnDemand(
            wsId: fixture.workspaceId,
            state: fixture.controller.workspaceManager.niriViewportState(for: fixture.workspaceId),
            engine: fixture.engine,
            monitor: fixture.monitor,
            animationTime: targetTime
        ))

        XCTAssertTrue(ScrollTickTrace.shared.dump().contains("anim=false"))
        XCTAssertTrue(FrameApplyTrace.shared.dump().contains("target=\(TraceFormat.rect(proxyTarget))"))
        XCTAssertEqual(
            fixture.controller.axManager.recentFrameWriteFailureComponents(for: fixture.token.windowId),
            .all
        )
    }

    func testDirectFocusAnimationDoesNotCheckScreenCaptureAccess() throws {
        let fixture = try makeFixture()
        let accessChecks = Mutex(0)
        let cache = FocusScrollPreviewCache(screenCaptureAccess: {
            accessChecks.withLock { $0 += 1 }
            return false
        })
        let snapshot = try XCTUnwrap(fixture.controller.layoutRefreshController.niriHandler.makeWorkspaceSnapshot(
            workspaceId: fixture.workspaceId,
            monitor: fixture.monitor,
            options: .init(
                viewportState: nil,
                useScrollAnimationPath: false,
                removalSeed: nil,
                isActiveWorkspace: true
            )
        ))
        XCTAssertEqual(fixture.controller.workspaceManager.interactionMonitorId, fixture.monitor.id)

        cache.reconcile(
            snapshot: snapshot,
            frames: [:],
            workspaceManager: fixture.controller.workspaceManager,
            animationsEnabled: true,
            animationStyle: .direct
        )
        XCTAssertEqual(accessChecks.withLock { $0 }, 0)

        cache.reconcile(
            snapshot: snapshot,
            frames: [:],
            workspaceManager: fixture.controller.workspaceManager,
            animationsEnabled: true,
            animationStyle: .smoothPreview
        )
        XCTAssertEqual(accessChecks.withLock { $0 }, 1)
    }

    private func addWindowAndTargetFrame(to fixture: Fixture) throws -> CGRect {
        fixture.controller.workspaceManager.withEngineMutationScope(in: fixture.workspaceId) {
            fixture.engine.addWindow(
                token: fixture.token,
                to: fixture.workspaceId,
                afterSelection: nil
            )
        }
        let gap = fixture.controller.innerGap(for: fixture.monitor)
        let frames = fixture.engine.calculateLayout(
            state: fixture.controller.workspaceManager.niriViewportState(for: fixture.workspaceId),
            workspaceId: fixture.workspaceId,
            monitorFrame: fixture.controller.insetWorkingFrame(for: fixture.monitor),
            gaps: (horizontal: gap, vertical: gap),
            orientation: .horizontal
        )
        return try XCTUnwrap(frames[fixture.token])
    }

    private func makeFixture() throws -> Fixture {
        let controller = makeController()
        let monitor = Monitor(
            id: .init(displayId: 95_100),
            displayId: 95_100,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 860),
            hasNotch: false,
            name: "Niri Layout Build Metrics"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        controller.niriLayoutHandler.enableNiriLayout()
        let workspaceId = try XCTUnwrap(
            controller.workspaceManager.workspaceId(for: "1", createIfMissing: true)
        )
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(95_101), windowId: 9_511),
            pid: 95_101,
            windowId: 9_511,
            to: workspaceId
        )
        let engine = try XCTUnwrap(controller.niriEngine)
        return Fixture(
            controller: controller,
            engine: engine,
            monitor: monitor,
            workspaceId: workspaceId,
            token: token
        )
    }

    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "NiriLayoutBuildMetricsRegressionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
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
        return WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
    }
}

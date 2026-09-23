// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import QuartzCore

@MainActor
final class FocusScrollProxyCoordinator {
    struct TestTargetLayout {
        let workspaceId: WorkspaceDescriptor.ID
        let frames: [WindowToken: CGRect]
        let hiddenHandles: [WindowToken: HideSide]
    }

    private struct Session {
        let id: UInt64
        let workspaceId: WorkspaceDescriptor.ID
        let displayId: CGDirectDisplayID
        let targetFrames: [WindowToken: CGRect]
        let targetHiddenHandles: [WindowToken: HideSide]
        let visibleTokens: [WindowToken]
        let startedAt: CFTimeInterval
    }

    private weak var controller: WMController?
    private let cache: FocusScrollPreviewCache
    private var panel: FocusScrollProxyPanel?
    private var session: Session?
    private var nextSessionId: UInt64 = 0
    private var settlementTask: Task<Void, Never>?
    private var startedCount = 0
    private var settledCount = 0
    private var timeoutCount = 0
    private var lastDurationMs = 0
    private var lastSkipReason = "none"
    var targetLayoutForTests: TestTargetLayout?

    init(controller: WMController?, cache: FocusScrollPreviewCache) {
        self.controller = controller
        self.cache = cache
    }

    @discardableResult
    func start(
        workspaceId: WorkspaceDescriptor.ID,
        displayId: CGDirectDisplayID,
        workingFrame: CGRect,
        oldFrames: [WindowToken: CGRect],
        targetLayout: (frames: [WindowToken: CGRect], hiddenHandles: [WindowToken: HideSide])
    ) -> Bool {
        guard let controller else { return skip("no-controller") }
        guard cache.workspaceId == workspaceId, cache.displayId == displayId,
              cache.captureAllowed else { return skip("cache-unavailable") }
        guard controller.workspaceManager.floatingEntries(in: workspaceId).isEmpty else {
            return skip("floating-window")
        }
        guard let wallpaper = cache.wallpaper(for: displayId) else { return skip("wallpaper-unavailable") }

        let currentFrames = startingFrames(oldFrames, workspaceId: workspaceId, displayId: displayId)
        let visibleTokens = Self.animationTokens(
            from: currentFrames, to: targetLayout.frames, workingFrame: workingFrame
        )
        guard !visibleTokens.isEmpty, visibleTokens.count <= 6,
              visibleTokens.contains(where: { token in
                  guard let old = currentFrames[token], let target = targetLayout.frames[token] else { return false }
                  return !old.approximatelyEqual(to: target, tolerance: FrameTolerance.frameWrite)
              }),
              let previews = cache.previews(for: visibleTokens)
        else { return skip("frames-or-previews-unavailable") }

        settlementTask?.cancel()
        startedCount += 1
        lastSkipReason = "none"
        nextSessionId &+= 1
        let id = nextSessionId
        session = Session(
            id: id,
            workspaceId: workspaceId,
            displayId: displayId,
            targetFrames: targetLayout.frames,
            targetHiddenHandles: targetLayout.hiddenHandles,
            visibleTokens: visibleTokens,
            startedAt: CACurrentMediaTime()
        )
        if panel == nil || panel?.frame != workingFrame.integral {
            panel?.dismiss()
            panel?.close()
            panel = FocusScrollProxyPanel(frame: workingFrame, displayId: displayId, wallpaper: wallpaper)
        }
        panel?.animate(
            from: currentFrames,
            to: targetLayout.frames,
            previews: previews,
            duration: 0.22
        ) { [weak self] in
            self?.animationCompleted(id: id)
        }
        return true
    }

    func targetLayout(
        for workspaceId: WorkspaceDescriptor.ID
    ) -> (frames: [WindowToken: CGRect], hiddenHandles: [WindowToken: HideSide])? {
        if let targetLayoutForTests, targetLayoutForTests.workspaceId == workspaceId {
            return (targetLayoutForTests.frames, targetLayoutForTests.hiddenHandles)
        }
        guard session?.workspaceId == workspaceId else { return nil }
        guard let session else { return nil }
        return (session.targetFrames, session.targetHiddenHandles)
    }

    func cancel() {
        settlementTask?.cancel()
        settlementTask = nil
        session = nil
        panel?.dismiss()
        panel?.close()
        panel = nil
    }

    func cancel(for workspaceId: WorkspaceDescriptor.ID) {
        guard session?.workspaceId == workspaceId else { return }
        cancel()
    }

    var diagnostics: String {
        let summary = "started=\(startedCount) settled=\(settledCount) timedOut=\(timeoutCount)"
            + " lastDurationMs=\(lastDurationMs) lastSkip=\(lastSkipReason)"
        guard let session else { return "active=false \(summary)" }
        return "active=true \(summary)"
            + " workspace=\(session.workspaceId.uuidString) display=\(session.displayId)"
            + " windows=\(session.visibleTokens.count) ageMs=\(Int((CACurrentMediaTime() - session.startedAt) * 1000))"
    }

    private func skip(_ reason: String) -> Bool {
        lastSkipReason = reason
        return false
    }

    private func startingFrames(
        _ oldFrames: [WindowToken: CGRect],
        workspaceId: WorkspaceDescriptor.ID,
        displayId: CGDirectDisplayID
    ) -> [WindowToken: CGRect] {
        guard session?.workspaceId == workspaceId, session?.displayId == displayId, let panel else {
            return oldFrames
        }
        return oldFrames.merging(panel.presentationFrames()) { _, presented in presented }
    }

    private static func animationTokens(
        from currentFrames: [WindowToken: CGRect],
        to targetFrames: [WindowToken: CGRect],
        workingFrame: CGRect
    ) -> [WindowToken] {
        Set(currentFrames.filter { $0.value.intersects(workingFrame) }.keys)
            .union(targetFrames.filter { $0.value.intersects(workingFrame) }.keys)
            .filter { currentFrames[$0] != nil && targetFrames[$0] != nil }
            .sorted { $0.windowId < $1.windowId }
    }

    private func animationCompleted(id: UInt64) {
        guard session?.id == id else { return }
        settlementTask?.cancel()
        settlementTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let session = self.session, session.id == id {
                if self.controller?.workspaceManager.activeWorkspaceOrFirst(
                    on: Monitor.ID(displayId: session.displayId)
                )?.id != session.workspaceId {
                    self.cancel()
                    return
                }
                if self.isSettled(session) {
                    self.settledCount += 1
                    self.lastDurationMs = Int((CACurrentMediaTime() - session.startedAt) * 1000)
                    self.cancel()
                    return
                }
                if CACurrentMediaTime() - session.startedAt >= 1.5 {
                    self.timeoutCount += 1
                    self.lastDurationMs = Int((CACurrentMediaTime() - session.startedAt) * 1000)
                    self.cancel()
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func isSettled(_ session: Session) -> Bool {
        guard let controller, let engine = controller.niriEngine else { return true }
        let state = controller.workspaceManager.niriViewportState(for: session.workspaceId)
        guard !hasPendingNiriAnimationWork(
            state: state,
            driver: controller.workspaceManager.animationDriver,
            engine: engine,
            workspaceId: session.workspaceId
        ) else { return false }
        let axManager = controller.axManager
        return session.visibleTokens.allSatisfy { token in
            if session.targetHiddenHandles[token] != nil {
                return !axManager.pendingParkWindowIds.contains(token.windowId)
            }
            guard let target = session.targetFrames[token],
                  let applied = axManager.lastAppliedFrame(for: token.windowId)
            else { return false }
            return !axManager.hasPendingFrameWrite(for: token.windowId)
                && applied.approximatelyEqual(to: target, tolerance: 1.5)
        }
    }
}

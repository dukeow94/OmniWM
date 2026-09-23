// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import CoreGraphics

@MainActor
final class FocusScrollPreviewCache {
    private let capture: FocusScrollSnapshotCapture
    private let screenCaptureAccess: () -> Bool
    private let wallpaperCache = OverviewWallpaperCache()
    private var handlesByToken: [WindowToken: WindowHandle] = [:]
    private var requestedTokens: [WindowToken] = []
    private(set) var workspaceId: WorkspaceDescriptor.ID?
    private(set) var displayId: CGDirectDisplayID?
    private(set) var captureAllowed = false

    init(
        capture: FocusScrollSnapshotCapture = FocusScrollSnapshotCapture(),
        screenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.capture = capture
        self.screenCaptureAccess = screenCaptureAccess
    }

    func reconcile(
        snapshot: NiriWorkspaceSnapshot,
        frames: [WindowToken: CGRect],
        workspaceManager: WorkspaceManager,
        animationsEnabled: Bool,
        animationStyle: FocusScrollAnimationStyle
    ) {
        guard animationsEnabled, animationStyle == .smoothPreview else {
            clear()
            return
        }
        guard snapshot.isActiveWorkspace,
              workspaceManager.interactionMonitorId == snapshot.monitor.monitorId
        else { return }
        guard screenCaptureAccess() else {
            clear()
            return
        }

        let eligible = Set(snapshot.windows.compactMap { window -> WindowToken? in
            guard !window.isNativeFullscreenSuspended,
                  !snapshot.excludedTokens.contains(window.token)
            else { return nil }
            return window.token
        })
        let selected = workspaceManager.selectedManagedToken
        let tokens = Self.candidates(
            frames: frames.filter { eligible.contains($0.key) },
            workingFrame: snapshot.monitor.workingFrame,
            selected: selected
        )
        let scale = min(snapshot.monitor.scale, 1.5)
        let requests = tokens.compactMap { token -> OverviewPreviewRequest? in
            guard let handle = workspaceManager.handle(for: token),
                  let frame = frames[token]
            else { return nil }
            return OverviewPreviewRequest(
                handle: handle,
                pixelWidth: min(4096, Int(ceil(frame.width * scale))),
                pixelHeight: min(4096, Int(ceil(frame.height * scale))),
                framesPerSecond: 2
            )
        }
        captureAllowed = true
        workspaceId = snapshot.workspaceId
        displayId = snapshot.monitor.displayId
        handlesByToken = Dictionary(uniqueKeysWithValues: requests.map { ($0.token, $0.handle) })
        requestedTokens = requests.map(\.token)
        capture.reconcile(requests)
        _ = wallpaperCache.image(for: snapshot.monitor.displayId, maxPixelSize: 4096)
    }

    func wallpaper(for displayId: CGDirectDisplayID) -> CGImage? {
        wallpaperCache.image(for: displayId, maxPixelSize: 4096)
    }

    func previews(for tokens: [WindowToken]) -> [WindowToken: OverviewPreviewFrame]? {
        var previews: [WindowToken: OverviewPreviewFrame] = [:]
        for token in tokens {
            guard handlesByToken[token] != nil, let frame = capture.preview(for: token) else { return nil }
            previews[token] = frame
        }
        return previews
    }

    func clear() {
        capture.clear()
        wallpaperCache.clear()
        handlesByToken.removeAll()
        requestedTokens.removeAll()
        workspaceId = nil
        displayId = nil
        captureAllowed = false
    }

    var diagnostics: String {
        let ready = requestedTokens.reduce(0) { count, token in
            count + (capture.preview(for: token) == nil ? 0 : 1)
        }
        return "captureAllowed=\(captureAllowed) display=\(displayId.map(String.init) ?? "none")"
            + " requested=\(requestedTokens.count) ready=\(ready) snapshots=\(capture.completedCaptureCount)"
            + " cachedBytes=\(capture.cachedByteCount)"
    }

    static func candidates(
        frames: [WindowToken: CGRect],
        workingFrame: CGRect,
        selected: WindowToken?,
        maximumCount: Int = 6
    ) -> [WindowToken] {
        guard workingFrame.width > 0, workingFrame.height > 0, maximumCount > 0 else { return [] }
        let captureRegion = workingFrame.insetBy(dx: -workingFrame.width, dy: -workingFrame.height)
        return frames.filter { _, frame in
            frame.width > 0 && frame.height > 0 && frame.intersects(captureRegion)
        }.sorted { left, right in
            if left.key == selected { return true }
            if right.key == selected { return false }
            let leftDistance = hypot(
                left.value.midX - workingFrame.midX,
                left.value.midY - workingFrame.midY
            )
            let rightDistance = hypot(
                right.value.midX - workingFrame.midX,
                right.value.midY - workingFrame.midY
            )
            return leftDistance == rightDistance
                ? left.key.windowId < right.key.windowId
                : leftDistance < rightDistance
        }.prefix(maximumCount).map(\.key)
    }
}

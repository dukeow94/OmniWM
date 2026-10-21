// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import CoreMedia
import ScreenCaptureKit

@MainActor
final class FocusScrollSnapshotCapture {
    typealias SnapshotProvider = @MainActor ([OverviewPreviewRequest]) async -> [WindowToken: OverviewPreviewFrame]

    private let snapshotProvider: SnapshotProvider?
    private var requestsByToken: [WindowToken: OverviewPreviewRequest] = [:]
    private var scheduledRequestsByToken: [WindowToken: OverviewPreviewRequest] = [:]
    private var previewsByToken: [WindowToken: OverviewPreviewFrame] = [:]
    private var windowsByToken: [WindowToken: SCWindow] = [:]
    private var captureTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private(set) var completedCaptureCount = 0

    init(snapshotProvider: SnapshotProvider? = nil) {
        self.snapshotProvider = snapshotProvider
    }

    func reconcile(_ requests: [OverviewPreviewRequest]) {
        let nextRequests = Dictionary(uniqueKeysWithValues: requests.map { ($0.token, $0) })
        for token in previewsByToken.keys where nextRequests[token] == nil {
            previewsByToken.removeValue(forKey: token)
        }
        let needsCapture = nextRequests != scheduledRequestsByToken
        requestsByToken = nextRequests
        guard !nextRequests.isEmpty else {
            scheduledRequestsByToken.removeAll()
            stop()
            return
        }
        guard needsCapture else { return }
        scheduledRequestsByToken = nextRequests
        generation &+= 1
        stop()
        let expectedGeneration = generation
        captureTask = Task { @MainActor [weak self] in
            await self?.captureOnce(expectedGeneration: expectedGeneration)
        }
    }

    func preview(for token: WindowToken) -> OverviewPreviewFrame? {
        previewsByToken[token]
    }

    var cachedByteCount: Int {
        previewsByToken.values.reduce(0) { $0 + $1.surface.allocationSize }
    }

    func clear() {
        generation &+= 1
        stop()
        requestsByToken.removeAll()
        scheduledRequestsByToken.removeAll()
        previewsByToken.removeAll()
        windowsByToken.removeAll()
        completedCaptureCount = 0
    }

    private func stop() {
        captureTask?.cancel()
        captureTask = nil
    }

    private func captureOnce(expectedGeneration: UInt64) async {
        defer {
            if generation == expectedGeneration { captureTask = nil }
        }
        let requests = requestsByToken.values.sorted { $0.token.windowId < $1.token.windowId }
        let captured = if let snapshotProvider {
            await snapshotProvider(requests)
        } else {
            await captureSnapshots(requests)
        }
        guard !Task.isCancelled, generation == expectedGeneration else { return }
        for (token, frame) in captured where requestsByToken[token] != nil {
            previewsByToken[token] = frame
        }
        completedCaptureCount += 1
    }

    private func captureSnapshots(
        _ requests: [OverviewPreviewRequest]
    ) async -> [WindowToken: OverviewPreviewFrame] {
        if requests.contains(where: { windowsByToken[$0.token] == nil }) {
            await discoverWindows()
        }
        var captured: [WindowToken: OverviewPreviewFrame] = [:]
        for request in requests {
            guard !Task.isCancelled, let window = windowsByToken[request.token] else { continue }
            let configuration = SCStreamConfiguration()
            configuration.width = request.pixelWidth
            configuration.height = request.pixelHeight
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.captureDynamicRange = .SDR
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.captureMicrophone = false
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            guard let sampleBuffer = try? await SCScreenshotManager.captureSampleBuffer(
                contentFilter: filter,
                configuration: configuration
            ), let frame = OverviewPreviewFrame(sampleBuffer: sampleBuffer)
            else { continue }
            captured[request.token] = frame
        }
        return captured
    }

    private func discoverWindows() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        ) else { return }
        windowsByToken = Dictionary(uniqueKeysWithValues: content.windows.compactMap { window in
            guard let application = window.owningApplication else { return nil }
            return (WindowToken(pid: application.processID, windowId: Int(window.windowID)), window)
        })
    }
}

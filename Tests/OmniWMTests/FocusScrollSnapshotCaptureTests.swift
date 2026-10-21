// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import Synchronization
import XCTest

@MainActor
final class FocusScrollSnapshotCaptureTests: XCTestCase {
    func testCapturesOncePerRequestSetAndStopsAfterClear() async {
        let calls = Mutex(0)
        let captured = expectation(description: "captured")
        let capture = FocusScrollSnapshotCapture { _ in
            calls.withLock { $0 += 1 }
            captured.fulfill()
            return [:]
        }
        let handle = WindowHandle(id: WindowToken(pid: 42, windowId: 7))
        let request = OverviewPreviewRequest(handle: handle, pixelWidth: 800, pixelHeight: 600, framesPerSecond: 2)
        capture.reconcile([request])

        await fulfillment(of: [captured], timeout: 1)
        capture.reconcile([request])
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(calls.withLock { $0 }, 1)

        capture.clear()
        let callsAfterClear = calls.withLock { $0 }
        try? await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(calls.withLock { $0 }, callsAfterClear)
    }
}

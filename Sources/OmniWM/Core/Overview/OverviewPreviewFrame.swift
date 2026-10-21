// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

final class OverviewPreviewFrame: @unchecked Sendable {
    private let pixelBuffer: CVPixelBuffer
    let surface: IOSurface
    let contentsRect: CGRect

    init?(pixelBuffer: CVPixelBuffer, contentRect: CGRect? = nil, scaleFactor: CGFloat = 1) {
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0, scaleFactor.isFinite, scaleFactor > 0 else { return nil }
        if let contentRect {
            let normalized = CGRect(
                x: contentRect.minX * scaleFactor / width,
                y: contentRect.minY * scaleFactor / height,
                width: contentRect.width * scaleFactor / width,
                height: contentRect.height * scaleFactor / height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !normalized.isNull, !normalized.isEmpty else { return nil }
            contentsRect = normalized
        } else {
            contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        self.surface = surface
        self.pixelBuffer = pixelBuffer
    }

    convenience init?(sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
              as? [[SCStreamFrameInfo: Any]],
              let metadata = attachments.first,
              let status = metadata[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return nil }
        let contentRect: CGRect?
        if let dictionary = metadata[.contentRect] as? [String: Any] {
            contentRect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        } else {
            contentRect = metadata[.contentRect] as? CGRect
        }
        let scaleFactor = (metadata[.scaleFactor] as? NSNumber)?.doubleValue ?? 1
        self.init(pixelBuffer: pixelBuffer, contentRect: contentRect, scaleFactor: scaleFactor)
    }
}

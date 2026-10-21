// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import QuartzCore

@MainActor
final class FocusScrollProxyPanel: NSPanel {
    private let rootLayer = CALayer()
    private let wallpaperLayer = CALayer()
    private var windowLayers: [WindowToken: CALayer] = [:]
    private var retainedPreviews: [WindowToken: OverviewPreviewFrame] = [:]
    private var generation: UInt64 = 0

    init(frame: CGRect, displayId: CGDirectDisplayID, wallpaper: CGImage?) {
        super.init(
            contentRect: frame.integral,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
        isRestorable = false
        level = .floating

        let view = NSView(frame: CGRect(origin: .zero, size: frame.integral.size))
        view.wantsLayer = true
        rootLayer.frame = view.bounds
        rootLayer.masksToBounds = true
        rootLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        wallpaperLayer.frame = rootLayer.bounds
        wallpaperLayer.contents = wallpaper
        wallpaperLayer.contentsGravity = .resizeAspectFill
        if let screen = NSScreen.screens.first(where: { $0.displayId == displayId }) {
            let displayFrame = screen.frame
            wallpaperLayer.contentsRect = CGRect(
                x: (frame.minX - displayFrame.minX) / displayFrame.width,
                y: (frame.minY - displayFrame.minY) / displayFrame.height,
                width: frame.width / displayFrame.width,
                height: frame.height / displayFrame.height
            )
        }
        rootLayer.addSublayer(wallpaperLayer)
        view.layer = rootLayer
        contentView = view
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }

    func animate(
        from oldFrames: [WindowToken: CGRect],
        to targetFrames: [WindowToken: CGRect],
        previews: [WindowToken: OverviewPreviewFrame],
        duration: CFTimeInterval,
        completion: @escaping @MainActor () -> Void
    ) {
        generation &+= 1
        let currentGeneration = generation
        for layer in windowLayers.values { layer.removeFromSuperlayer() }
        windowLayers.removeAll()
        retainedPreviews = previews

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.generation == currentGeneration else { return }
                completion()
            }
        }
        for (token, preview) in previews {
            guard let oldFrame = oldFrames[token], let targetFrame = targetFrames[token] else { continue }
            let layer = CALayer()
            layer.contents = preview.surface
            layer.contentsRect = preview.contentsRect
            layer.contentsGravity = .resize
            layer.frame = targetFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
            layer.actions = ["position": NSNull(), "bounds": NSNull()]
            rootLayer.addSublayer(layer)
            windowLayers[token] = layer

            let startFrame = oldFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = CGPoint(x: startFrame.midX, y: startFrame.midY)
            position.toValue = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            position.duration = duration
            position.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(position, forKey: "focusScroll.position")
            if startFrame.size != layer.frame.size {
                let bounds = CABasicAnimation(keyPath: "bounds")
                bounds.fromValue = CGRect(origin: .zero, size: startFrame.size)
                bounds.toValue = layer.bounds
                bounds.duration = duration
                bounds.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(bounds, forKey: "focusScroll.bounds")
            }
        }
        orderFront(nil)
        CATransaction.commit()
    }

    func dismiss() {
        generation &+= 1
        orderOut(nil)
        for layer in windowLayers.values { layer.removeFromSuperlayer() }
        windowLayers.removeAll()
        retainedPreviews.removeAll()
    }

    func presentationFrames() -> [WindowToken: CGRect] {
        Dictionary(uniqueKeysWithValues: windowLayers.map { token, layer in
            let localFrame = layer.presentation()?.frame ?? layer.frame
            return (token, localFrame.offsetBy(dx: frame.minX, dy: frame.minY))
        })
    }
}

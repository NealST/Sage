//
//  PanelSpringAnimator.swift
//  Sage
//

import AppKit
import QuartzCore

/// Critically damped height spring for the HUD panel.
/// Summon/dismiss stays instant; only occasional expand/collapse uses this.
@MainActor
final class PanelSpringAnimator: NSObject {
    private weak var panel: NSPanel?
    private var displayLink: CADisplayLink?
    private var currentHeight: CGFloat = SageDesign.HUD.minHeight
    private var velocity: CGFloat = 0
    private var targetHeight: CGFloat = SageDesign.HUD.minHeight
    private var topY: CGFloat = 0
    private var screenVisible: NSRect = .zero

    func attach(to panel: NSPanel) {
        self.panel = panel
        currentHeight = panel.frame.height
        targetHeight = currentHeight
    }

    /// Retarget from the live height (interruptible).
    func animate(to height: CGFloat, on screen: NSScreen) {
        guard let panel else { return }

        let clamped = min(
            max(height, SageDesign.HUD.minHeight + 28),
            SageDesign.HUD.maxHeight + 28
        )
        screenVisible = screen.visibleFrame
        topY = screenVisible.maxY - SageDesign.HUD.topOffset
        targetHeight = clamped
        currentHeight = panel.frame.height

        if AccessibilityPreferences.reduceMotion {
            velocity = 0
            applyFrame(height: clamped)
            stopDisplayLink()
            return
        }

        startDisplayLink(on: screen)
    }

    func snap(to height: CGFloat, on screen: NSScreen) {
        stopDisplayLink()
        velocity = 0
        screenVisible = screen.visibleFrame
        topY = screenVisible.maxY - SageDesign.HUD.topOffset
        let clamped = min(
            max(height, SageDesign.HUD.minHeight + 28),
            SageDesign.HUD.maxHeight + 28
        )
        targetHeight = clamped
        currentHeight = clamped
        applyFrame(height: clamped)
    }

    private func startDisplayLink(on screen: NSScreen) {
        guard displayLink == nil else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = max(link.duration, 1.0 / 120.0)
        let safeDt = min(dt, 1.0 / 20.0)

        let response = SageDesign.Motion.expandResponse
        let damping = SageDesign.Motion.expandDampingRatio
        let omega = (2 * CGFloat.pi) / response

        let displacement = currentHeight - targetHeight
        let spring = -omega * omega * displacement
        let damper = -2 * damping * omega * velocity
        let acceleration = spring + damper

        velocity += acceleration * CGFloat(safeDt)
        currentHeight += velocity * CGFloat(safeDt)

        applyFrame(height: currentHeight)

        let settled = abs(currentHeight - targetHeight) < 0.35 && abs(velocity) < 8
        if settled {
            currentHeight = targetHeight
            velocity = 0
            applyFrame(height: targetHeight)
            stopDisplayLink()
        }
    }

    private func applyFrame(height: CGFloat) {
        guard let panel else { return }
        // Extra width matches HUDView's shadow padding (12pt each side).
        let width = SageDesign.HUD.width + 24
        let size = NSSize(width: width, height: height)
        let x = screenVisible.midX - size.width / 2
        let y = topY - size.height
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        // Keep hosting height in lockstep — autoresizing is width-only by design.
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
    }
}

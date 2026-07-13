//
//  RotationDialPlateView.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// A circular rotation dial (an alternative to the horizontal ``RotationDialView``).
/// Rotate the plate with a finger; a fixed top pointer marks the current angle.
public final class RotationDialPlateView: UIView {

    /// Snap-to-0 threshold basis, in radians. The plate rotates a full 360°
    /// continuously, wrapping back to 0 after a complete turn.
    public var range: CGFloat = .pi
    public var onChange: ((CGFloat) -> Void)?
    public private(set) var angle: CGFloat = 0 { didSet { setNeedsDisplay() } }

    private var lastTouchAngle: CGFloat?
    private let haptic = UISelectionFeedbackGenerator()
    private var wasSnapped = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError() }

    /// Normalize any angle into `(-π, π]` so a full turn wraps back to 0.
    private func wrapped(_ value: CGFloat) -> CGFloat {
        let twoPi = 2 * CGFloat.pi
        var x = value.truncatingRemainder(dividingBy: twoPi)
        if x > .pi { x -= twoPi } else if x <= -.pi { x += twoPi }
        return x
    }

    public func setAngle(_ value: CGFloat) {
        angle = wrapped(value)
        onChange?(angle)
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let touchAngle = atan2(p.y - center.y, p.x - center.x)
        switch g.state {
        case .began: lastTouchAngle = touchAngle; haptic.prepare()
        case .changed:
            guard let last = lastTouchAngle else { return }
            lastTouchAngle = touchAngle
            // Wrap the incremental delta too, so crossing the ±π seam is seamless.
            var a = wrapped(angle + wrapped(touchAngle - last))   // full 360° — wraps at a turn
            if abs(a) < range * 0.03 {
                a = 0
                if !wasSnapped { haptic.selectionChanged(); wasSnapped = true }
            } else { wasSnapped = false }
            angle = a
            onChange?(a)
        default: lastTouchAngle = nil
        }
    }

    public override func draw(_ rect: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 6

        // Rotating tick plate.
        UIColor.white.withAlphaComponent(0.4).setStroke()
        let ticks = UIBezierPath()
        let step = CGFloat.pi / 36    // every 5°
        var t = -CGFloat.pi
        while t < .pi {
            let a = t - angle
            let outer = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            let inner = CGPoint(x: center.x + cos(a) * (radius - 8), y: center.y + sin(a) * (radius - 8))
            ticks.move(to: inner); ticks.addLine(to: outer)
            t += step
        }
        ticks.lineWidth = 1
        ticks.stroke()

        // Fixed top pointer.
        UIColor.systemYellow.setFill()
        let pointer = UIBezierPath()
        pointer.move(to: CGPoint(x: center.x, y: center.y - radius - 2))
        pointer.addLine(to: CGPoint(x: center.x - 5, y: center.y - radius - 12))
        pointer.addLine(to: CGPoint(x: center.x + 5, y: center.y - radius - 12))
        pointer.close(); pointer.fill()

        let degrees = Int((angle * 180 / .pi).rounded())
        let text = "\(degrees)°" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
    }
}

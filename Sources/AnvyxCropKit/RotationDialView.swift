//
//  RotationDialView.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// A horizontal rotation dial. Drag to change the angle — it rotates a full 360°
/// continuously, wrapping back to 0 after a complete turn, and snaps to 0 with
/// haptic feedback. Wire ``onChange`` to `CropperView.rotationAngle`.
public final class RotationDialView: UIView {

    /// Angle swept by a half-width drag, in radians; also sets the snap-to-0
    /// threshold. A full-width drag rotates a full 360°.
    public var range: CGFloat = .pi
    public var onChange: ((CGFloat) -> Void)?

    public private(set) var angle: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    private var startAngle: CGFloat = 0
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
        let t = g.translation(in: self).x
        let sensitivity = range / max(1, bounds.width / 2)
        switch g.state {
        case .began: startAngle = angle; haptic.prepare()
        case .changed:
            var a = wrapped(startAngle - t * sensitivity)   // full 360° — wraps at a turn
            if abs(a) < range * 0.03 {          // snap to 0
                a = 0
                if !wasSnapped { haptic.selectionChanged(); wasSnapped = true }
            } else { wasSnapped = false }
            angle = a
            onChange?(a)
        default: break
        }
    }

    public override func draw(_ rect: CGRect) {
        let mid = bounds.midX
        let spacing: CGFloat = 12
        UIColor.white.withAlphaComponent(0.4).setStroke()
        let ticks = UIBezierPath()
        var x = mid.truncatingRemainder(dividingBy: spacing)
        while x < bounds.width {
            let tall = abs(x - mid) < 1
            ticks.move(to: CGPoint(x: x, y: bounds.midY - (tall ? 12 : 6)))
            ticks.addLine(to: CGPoint(x: x, y: bounds.midY + (tall ? 12 : 6)))
            x += spacing
        }
        ticks.lineWidth = 1
        ticks.stroke()

        // Center indicator + degrees.
        UIColor.systemYellow.setStroke()
        let indicator = UIBezierPath()
        indicator.move(to: CGPoint(x: mid, y: bounds.minY))
        indicator.addLine(to: CGPoint(x: mid, y: bounds.maxY))
        indicator.lineWidth = 2
        indicator.stroke()

        let degrees = Int((angle * 180 / .pi).rounded())
        let text = "\(degrees)°" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: mid - size.width / 2, y: bounds.maxY - size.height), withAttributes: attrs)
    }
}

#if os(iOS) || os(tvOS) || os(visionOS) || os(macCatalyst)
import UIKit

// MARK: - Touch input
//
// Gesture map for v1:
//   - Single tap                -> left click at tapped point
//   - Two-finger tap            -> right click at tapped point
//   - Long press + drag         -> left button held while dragging (drag-select)
//   - Pan (one finger)          -> move pointer without clicking
//
// Pinch/zoom/scroll are handled by the enclosing scroll view wrapper, not here.

extension VNCCAFramebufferView {
	struct UInt16Point {
		let x: UInt16
		let y: UInt16
	}

	func installGestureRecognizers() {
		isMultipleTouchEnabled = true
		isUserInteractionEnabled = true

		let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
		singleTap.numberOfTapsRequired = 1
		singleTap.numberOfTouchesRequired = 1
		addGestureRecognizer(singleTap)

		let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
		twoFingerTap.numberOfTapsRequired = 1
		twoFingerTap.numberOfTouchesRequired = 2
		addGestureRecognizer(twoFingerTap)

		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressDrag(_:)))
		longPress.minimumPressDuration = 0.35
		longPress.allowableMovement = .greatestFiniteMagnitude
		addGestureRecognizer(longPress)

		let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
		pan.minimumNumberOfTouches = 1
		pan.maximumNumberOfTouches = 1
		// Only start after long-press has failed — otherwise long-press drag never wins.
		pan.require(toFail: longPress)
		addGestureRecognizer(pan)
	}

	@objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
		guard let connection,
		      let point = scaledContentRelativePosition(ofLocationIn: gesture) else {
			return
		}

		connection.mouseButtonDown(.left, x: point.x, y: point.y)
		connection.mouseButtonUp(.left, x: point.x, y: point.y)
	}

	@objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
		guard let connection,
		      let point = scaledContentRelativePosition(ofLocationIn: gesture) else {
			return
		}

		connection.mouseButtonDown(.right, x: point.x, y: point.y)
		connection.mouseButtonUp(.right, x: point.x, y: point.y)
	}

	@objc private func handleLongPressDrag(_ gesture: UILongPressGestureRecognizer) {
		guard let connection,
		      let point = scaledContentRelativePosition(ofLocationIn: gesture) else {
			return
		}

		switch gesture.state {
		case .began:
			connection.mouseButtonDown(.left, x: point.x, y: point.y)
		case .changed:
			connection.mouseButtonDown(.left, x: point.x, y: point.y)
		case .ended, .cancelled, .failed:
			connection.mouseButtonUp(.left, x: point.x, y: point.y)
		default:
			break
		}
	}

	@objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
		guard let connection,
		      let point = scaledContentRelativePosition(ofLocationIn: gesture) else {
			return
		}

		connection.mouseMove(x: point.x, y: point.y)
	}

	private func scaledContentRelativePosition(ofLocationIn gesture: UIGestureRecognizer) -> UInt16Point? {
		let viewPoint = gesture.location(in: self)
		return scaledContentRelativePosition(of: viewPoint)
	}

	private func scaledContentRelativePosition(of viewPoint: CGPoint) -> UInt16Point? {
		let rect = contentRect

		guard rect.contains(viewPoint) else {
			return nil
		}

		let scale = scaleRatio
		guard scale > 0 else { return nil }

		let scaledX = (viewPoint.x - rect.origin.x) / scale
		let scaledY = (viewPoint.y - rect.origin.y) / scale

		let clampedX = max(0, min(scaledX, framebufferSize.width - 1))
		let clampedY = max(0, min(scaledY, framebufferSize.height - 1))

		return UInt16Point(x: UInt16(clampedX), y: UInt16(clampedY))
	}
}
#endif

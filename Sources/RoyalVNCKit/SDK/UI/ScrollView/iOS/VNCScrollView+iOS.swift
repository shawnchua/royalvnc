#if os(iOS) || os(tvOS) || os(visionOS) || os(macCatalyst)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import UIKit

/// UIScrollView wrapper for a `VNCCAFramebufferView`. Provides pinch-to-zoom
/// and centers the content when smaller than the viewport.
///
/// Gesture ownership: the scroll view's own pan is limited to two-finger
/// touches so that the framebuffer view's one-finger pan (pointer move)
/// continues to win. Pinch remains two-finger zoom.
@objc(VNCScrollView)
public final class VNCScrollView: UIScrollView, UIScrollViewDelegate {
	@objc
	public private(set) var framebufferView: VNCCAFramebufferView?

	public override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		delegate = self
		showsVerticalScrollIndicator = false
		showsHorizontalScrollIndicator = false
		bouncesZoom = true
		minimumZoomScale = 1.0
		maximumZoomScale = 4.0
		// Let the framebuffer view own one-finger pan (pointer move).
		panGestureRecognizer.minimumNumberOfTouches = 2
		panGestureRecognizer.maximumNumberOfTouches = 2

		if #available(iOS 11.0, tvOS 11.0, *) {
			contentInsetAdjustmentBehavior = .never
		}
	}

	@objc(installFramebufferView:)
	public func install(framebufferView view: VNCCAFramebufferView) {
		self.framebufferView?.removeFromSuperview()
		framebufferView = view

		view.frame = CGRect(origin: .zero, size: view.framebufferSize)
		addSubview(view)
		contentSize = view.framebufferSize

		setNeedsLayout()
	}

	public override func layoutSubviews() {
		super.layoutSubviews()
		centerContent()
	}

	private func centerContent() {
		guard let framebufferView else { return }

		let boundsSize = bounds.size
		let contentSize = framebufferView.frame.size

		let insetX = max(0, (boundsSize.width - contentSize.width) / 2)
		let insetY = max(0, (boundsSize.height - contentSize.height) / 2)

		contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
	}

	public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return framebufferView
	}

	public func scrollViewDidZoom(_ scrollView: UIScrollView) {
		centerContent()
	}
}
#endif

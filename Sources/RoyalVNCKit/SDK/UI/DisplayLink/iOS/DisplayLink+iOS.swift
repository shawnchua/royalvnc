#if os(iOS) || os(tvOS) || os(visionOS) || os(macCatalyst)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import UIKit
import QuartzCore

protocol DisplayLinkDelegate: AnyObject {
	func displayLinkDidUpdate(_ displayLink: DisplayLink)
}

final class DisplayLink {
	private let proxy: DisplayLinkProxy
	private let caDisplayLink: CADisplayLink

	weak var delegate: DisplayLinkDelegate?

	var isEnabled: Bool = false {
		didSet {
			guard oldValue != isEnabled else { return }
			caDisplayLink.isPaused = !isEnabled
		}
	}

	init?(screen: UIScreen) {
		let proxy = DisplayLinkProxy()
		self.proxy = proxy

		self.caDisplayLink = CADisplayLink(target: proxy,
		                                   selector: #selector(DisplayLinkProxy.tick(_:)))

		let maxFPS = Float(max(screen.maximumFramesPerSecond, 60))
		self.caDisplayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30,
		                                                              maximum: maxFPS,
		                                                              preferred: maxFPS)
		self.caDisplayLink.isPaused = true
		self.caDisplayLink.add(to: .main, forMode: .common)

		proxy.owner = self
	}

	deinit {
		caDisplayLink.invalidate()
	}

	fileprivate func didTick() {
		delegate?.displayLinkDidUpdate(self)
	}
}

private final class DisplayLinkProxy {
	weak var owner: DisplayLink?

	@objc func tick(_ link: CADisplayLink) {
		owner?.didTick()
	}
}
#endif

#if os(iOS) || os(tvOS) || os(visionOS) || os(macCatalyst)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import UIKit
import QuartzCore
import IOSurface
import Metal

@objc(VNCCAFramebufferView)
public final class VNCCAFramebufferView: UIView, VNCFramebufferView {
	@objc
	public private(set) weak var connection: VNCConnection?

	@objc
	public private(set) weak var delegate: VNCConnectionDelegate?

	@objc
	public let settings: VNCConnection.Settings

	@objc
	public var accumulatedScrollDeltaX: CGFloat = 0

	@objc
	public var accumulatedScrollDeltaY: CGFloat = 0

	@objc
	private(set) weak var framebuffer: VNCFramebuffer?

	@objc
	private(set) public var framebufferSize: CGSize

	@objc
	private(set) public var scrollStep: CGFloat = 12

	@objc
	public private(set) var currentCursor: VNCCursor = .empty

	@objc
	public var scaleRatio: CGFloat {
		let containerBounds = bounds
		let fbSize = framebufferSize

		guard containerBounds.width > 0,
			  containerBounds.height > 0,
			  fbSize.width > 0,
			  fbSize.height > 0 else {
			return 1
		}

		let targetAspectRatio = containerBounds.width / containerBounds.height
		let fbAspectRatio = fbSize.width / fbSize.height

		let ratio: CGFloat

		if fbAspectRatio >= targetAspectRatio {
			ratio = containerBounds.width / framebufferSize.width
		} else {
			ratio = containerBounds.height / framebufferSize.height
		}

		// Only allow downscaling, no upscaling
		guard ratio < 1 else { return 1 }

		return ratio
	}

	@objc
	public var contentRect: CGRect {
		let containerBounds = bounds
		let scale = scaleRatio

		var rect = CGRect(x: 0, y: 0,
						  width: framebufferSize.width * scale, height: framebufferSize.height * scale)

		if rect.size.width < containerBounds.size.width {
			rect.origin.x = (containerBounds.size.width - rect.size.width) / 2.0
		}

		if rect.size.height < containerBounds.size.height {
			rect.origin.y = (containerBounds.size.height - rect.size.height) / 2.0
		}

		return rect
	}

	public override var canBecomeFirstResponder: Bool { true }

	private var displayLink: DisplayLink?

	private static let enableMetalRendering = true

	private let renderQueue = DispatchQueue(label: "com.royalvnc.framebufferview.metal",
	                                        qos: .userInteractive)

	private let renderSemaphore = DispatchSemaphore(value: 1)

	private var isMetalEnabled = false
	private var isMetalActive = false
	private let pixelFormat = MTLPixelFormat.bgra8Unorm

	private var metalDevice: MTLDevice?
	private var commandQueue: MTLCommandQueue?
	private var metalLayer: CAMetalLayer?

	private var ioSurfaceTexture: MTLTexture?
	private var currentIOSurface: IOSurface?
	private var currentIOSurfaceSize: CGSize = .zero

	@objc
	public init(frame frameRect: CGRect,
	            framebuffer: VNCFramebuffer,
	            connection: VNCConnection,
	            connectionDelegate: VNCConnectionDelegate) {
		self.framebufferSize = framebuffer.size.cgSize
		self.framebuffer = framebuffer
		self.connection = connection
		self.settings = connection.settings
		self.delegate = connectionDelegate

		super.init(frame: frameRect)

		connection.delegate = self

		let layer = self.layer

		// Set some properties that might(!) boost performance a bit
		layer.drawsAsynchronously = true
		layer.isOpaque = true
		layer.masksToBounds = false
		layer.allowsEdgeAntialiasing = false
		layer.backgroundColor = UIColor.clear.cgColor

		if Self.enableMetalRendering,
		   let device = MTLCreateSystemDefaultDevice(),
		   let commandQueue = device.makeCommandQueue() {
			self.isMetalEnabled = true
			self.metalDevice = device
			self.commandQueue = commandQueue

			let metalLayer = CAMetalLayer()
			metalLayer.device = device
			metalLayer.pixelFormat = pixelFormat
			metalLayer.framebufferOnly = false
			metalLayer.isOpaque = true
			metalLayer.backgroundColor = UIColor.clear.cgColor
			metalLayer.contentsScale = 1
			metalLayer.presentsWithTransaction = false
			metalLayer.allowsNextDrawableTimeout = false

			layer.addSublayer(metalLayer)

			self.metalLayer = metalLayer

			let shouldUseMetal = canUseMetal(for: framebuffer)
			setMetalLayerActive(shouldUseMetal)

			if !shouldUseMetal {
				configureFallbackLayer(layer)
			}
		} else {
			self.isMetalEnabled = false
			self.isMetalActive = false
			self.metalDevice = nil
			self.commandQueue = nil

			configureFallbackLayer(layer)
		}

		frameSizeDidChange(frameRect.size)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		removeDisplayLink()
	}

	public override func didMoveToWindow() {
		super.didMoveToWindow()
		addDisplayLink()
	}

	public override func layoutSubviews() {
		super.layoutSubviews()
		frameSizeDidChange(bounds.size)
	}

	func removeDisplayLink() {
		guard settings.useDisplayLink else { return }
		guard let oldDisplayLink = self.displayLink else { return }

		oldDisplayLink.delegate = nil
		oldDisplayLink.isEnabled = false

		self.displayLink = nil
	}

	func addDisplayLink() {
		guard settings.useDisplayLink else { return }

		removeDisplayLink()

		guard let window else { return }

		let screen: UIScreen
		if #available(iOS 13.0, tvOS 13.0, *), let windowScene = window.windowScene {
			screen = windowScene.screen
		} else {
			screen = UIScreen.main
		}

		guard let displayLink = DisplayLink(screen: screen) else {
			return
		}

		displayLink.delegate = self

		self.displayLink = displayLink

		displayLink.isEnabled = true
	}
}

// MARK: - Rendering
private extension VNCCAFramebufferView {
	func configureFallbackLayer(_ layer: CALayer) {
		layer.contentsScale = 1
		layer.contentsGravity = .center
		layer.contentsFormat = .RGBA8Uint
		layer.minificationFilter = .trilinear
		layer.magnificationFilter = .trilinear
	}

	func canUseMetal(for framebuffer: VNCFramebuffer?) -> Bool {
		guard isMetalEnabled,
		      let framebuffer,
		      let surface = framebuffer.ioSurface else {
			return false
		}

		return isSurfaceAligned(surface)
	}

	func isSurfaceAligned(_ surface: IOSurface) -> Bool {
		return surface.bytesPerRow % 16 == 0
	}

	func setMetalLayerActive(_ isActive: Bool) {
		isMetalActive = isActive
		metalLayer?.isHidden = !isActive
	}

	func updateImage(_ image: CGImage?) {
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.layer.contents = image
		}
	}

	func requestRender() {
		guard self.isMetalActive else {
			updateImage(self.framebuffer?.cgImage)
			return
		}

		guard self.commandQueue != nil,
		      self.metalLayer != nil else {
			return
		}

		let renderSemaphore = self.renderSemaphore

		guard renderSemaphore.wait(timeout: .now()) == .success else {
			return
		}

		let framebuffer = self.framebuffer
		let framebufferSize = self.framebufferSize

		self.renderQueue.async { [weak self] in
			defer {
				renderSemaphore.signal()
			}

			guard let self else { return }

			self.renderIOSurface(framebuffer: framebuffer,
			                     framebufferSize: framebufferSize)
		}
	}

	func renderIOSurface(framebuffer: VNCFramebuffer?,
	                     framebufferSize: CGSize) {
		guard let metalLayer,
		      let commandQueue,
		      let framebuffer else {
			return
		}

		let width = Int(framebufferSize.width)
		let height = Int(framebufferSize.height)

		guard width > 0, height > 0 else { return }

		guard let ioSurfaceTexture = ensureIOSurfaceTexture(surface: framebuffer.ioSurface,
		                                                    size: framebufferSize) else {
			DispatchQueue.main.async { [weak self] in
				guard let self else { return }

				self.setMetalLayerActive(false)
				self.configureFallbackLayer(self.layer)
				self.frameSizeDidChange(self.bounds.size)
				self.updateImage(framebuffer.cgImage)
			}

			return
		}

		guard let drawable = metalLayer.nextDrawable() else {
			return
		}

		guard let commandBuffer = commandQueue.makeCommandBuffer(),
		      let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
			return
		}

		let zeroOrigin = MTLOrigin(x: 0, y: 0, z: 0)
		let sourceSize = MTLSize(width: width, height: height, depth: 1)

		blitEncoder.copy(from: ioSurfaceTexture,
		                 sourceSlice: 0,
		                 sourceLevel: 0,
		                 sourceOrigin: zeroOrigin,
		                 sourceSize: sourceSize,
		                 to: drawable.texture,
		                 destinationSlice: 0,
		                 destinationLevel: 0,
		                 destinationOrigin: zeroOrigin)

		blitEncoder.endEncoding()

		commandBuffer.present(drawable)
		commandBuffer.commit()
	}

	func ensureIOSurfaceTexture(surface: IOSurface?,
	                            size: CGSize) -> MTLTexture? {
		guard let surface,
		      self.isSurfaceAligned(surface),
		      let metalDevice else {
			return nil
		}

		if self.currentIOSurface !== surface ||
		   self.currentIOSurfaceSize != size ||
		   self.ioSurfaceTexture == nil {
			let width = Int(size.width)
			let height = Int(size.height)

			guard width > 0, height > 0 else { return nil }

			let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
			                                                          width: width,
			                                                          height: height,
			                                                          mipmapped: false)

			descriptor.usage = [ .shaderRead ]
			// iOS/tvOS/visionOS don't support .managed; .shared is required for IOSurface-backed textures.
			descriptor.storageMode = .shared

			self.ioSurfaceTexture = metalDevice.makeTexture(descriptor: descriptor,
			                                                iosurface: surface,
			                                                plane: 0)

			self.currentIOSurface = surface
			self.currentIOSurfaceSize = size
		}

		return self.ioSurfaceTexture
	}

	func frameSizeDidChange(_ size: CGSize) {
		if isMetalActive {
			updateMetalLayerLayout()
		} else {
			updateFallbackLayerLayout()
		}
	}

	func updateMetalLayerLayout() {
		guard let metalLayer else { return }

		let targetFrame: CGRect

		if settings.isScalingEnabled {
			targetFrame = self.contentRect
		} else {
			let origin = CGPoint(x: (bounds.size.width - framebufferSize.width) / 2.0,
			                     y: (bounds.size.height - framebufferSize.height) / 2.0)

			targetFrame = CGRect(origin: origin, size: framebufferSize)
		}

		CATransaction.begin()
		CATransaction.setDisableActions(true)

		metalLayer.frame = targetFrame
		metalLayer.drawableSize = framebufferSize

		CATransaction.commit()
	}

	func updateFallbackLayerLayout() {
		guard settings.isScalingEnabled else { return }

		if frameSizeExceedsFramebufferSize(bounds.size) {
			layer.contentsGravity = .center
		} else {
			layer.contentsGravity = .resizeAspect
		}
	}
}

extension VNCCAFramebufferView: DisplayLinkDelegate {
	func displayLinkDidUpdate(_ displayLink: DisplayLink) {
		requestRender()
	}
}

extension VNCCAFramebufferView: VNCConnectionDelegate {
	// Handle directly
	public func connection(
		_ connection: VNCConnection,
		didUpdateFramebuffer framebuffer: VNCFramebuffer,
		x: UInt16,
		y: UInt16,
		width: UInt16,
		height: UInt16
	) {
		guard !settings.useDisplayLink,
		      displayLink == nil else {
			return
		}

		requestRender()
	}

	// Handle directly
	public func connection(
		_ connection: VNCConnection,
		didUpdateCursor cursor: VNCCursor
	) {
		DispatchQueue.main.async { [weak self] in
			self?.currentCursor = cursor
		}
	}

	// Passthrough
	public func connection(
		_ connection: VNCConnection,
		stateDidChange connectionState: VNCConnection.ConnectionState
	) {
		delegate?.connection(connection, stateDidChange: connectionState)
	}

	// Passthrough
	public func connection(
		_ connection: VNCConnection,
		credentialFor authenticationType: VNCAuthenticationType,
		completion: @escaping ((any VNCCredential)?) -> Void
	) {
		guard let delegate else {
			completion(nil)
			return
		}

		delegate.connection(connection,
		                    credentialFor: authenticationType,
		                    completion: completion)
	}

	// Passthrough
	public func connection(
		_ connection: VNCConnection,
		didCreateFramebuffer framebuffer: VNCFramebuffer
	) {
		delegate?.connection(connection, didCreateFramebuffer: framebuffer)
	}

	// Passthrough
	public func connection(
		_ connection: VNCConnection,
		didResizeFramebuffer framebuffer: VNCFramebuffer
	) {
		delegate?.connection(connection, didResizeFramebuffer: framebuffer)
	}
}
#endif

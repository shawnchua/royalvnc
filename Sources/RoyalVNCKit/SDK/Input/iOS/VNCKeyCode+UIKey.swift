#if os(iOS) || os(tvOS) || os(visionOS) || os(macCatalyst)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import UIKit

public extension VNCKeyCode {
	static func keyCodesFrom(uiKey: UIKey) -> [VNCKeyCode] {
		if let mapped = VNCKeyCode.from(hidUsage: uiKey.keyCode) {
			return [ mapped ]
		}

		let chars = uiKey.charactersIgnoringModifiers
		guard !chars.isEmpty else { return [] }

		return VNCKeyCode.keyCodesFrom(characters: chars)
	}
}
#endif

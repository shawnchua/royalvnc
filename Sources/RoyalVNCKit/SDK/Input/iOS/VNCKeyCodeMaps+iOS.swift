#if os(iOS) || os(tvOS) || os(visionOS) || os(macCatalyst)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import UIKit

public extension VNCKeyCode {
	static func from(hidUsage: UIKeyboardHIDUsage) -> VNCKeyCode? {
		return VNCKeyCodeMapsIOS.hidToVNCKeyCodeMapping[hidUsage]
	}
}

private struct VNCKeyCodeMapsIOS {
	static let hidToVNCKeyCodeMapping: [UIKeyboardHIDUsage: VNCKeyCode] = [
		// Modifiers
		.keyboardLeftShift: .shift,
		.keyboardRightShift: .rightShift,
		.keyboardLeftControl: .control,
		.keyboardRightControl: .rightControl,
		.keyboardLeftAlt: .option,
		.keyboardRightAlt: .rightOption,
		.keyboardLeftGUI: .command,
		.keyboardRightGUI: .rightCommand,

		// Navigation / editing
		.keyboardReturnOrEnter: .return,
		.keyboardReturn: .return,
		.keyboardDeleteForward: .forwardDelete,
		.keyboardSpacebar: .space,
		.keyboardDeleteOrBackspace: .delete,
		.keyboardTab: .tab,
		.keyboardEscape: .escape,

		.keyboardLeftArrow: .leftArrow,
		.keyboardUpArrow: .upArrow,
		.keyboardRightArrow: .rightArrow,
		.keyboardDownArrow: .downArrow,

		.keyboardPageUp: .pageUp,
		.keyboardPageDown: .pageDown,
		.keyboardEnd: .end,
		.keyboardHome: .home,
		.keyboardInsert: .insert,

		// Keypad
		.keypadNumLock: .ansiKeypadClear,
		.keypadEqualSign: .ansiKeypadEquals,
		.keypadSlash: .ansiKeypadDivide,
		.keypadAsterisk: .ansiKeypadMultiply,
		.keypadHyphen: .ansiKeypadMinus,
		.keypadPlus: .ansiKeypadPlus,
		.keypadEnter: .ansiKeypadEnter,
		.keypadPeriod: .ansiKeypadDecimal,

		// Function keys
		.keyboardF1: .f1,
		.keyboardF2: .f2,
		.keyboardF3: .f3,
		.keyboardF4: .f4,
		.keyboardF5: .f5,
		.keyboardF6: .f6,
		.keyboardF7: .f7,
		.keyboardF8: .f8,
		.keyboardF9: .f9,
		.keyboardF10: .f10,
		.keyboardF11: .f11,
		.keyboardF12: .f12,
		.keyboardF13: .f13,
		.keyboardF14: .f14,
		.keyboardF15: .f15,
		.keyboardF16: .f16,
		.keyboardF17: .f17,
		.keyboardF18: .f18,
		.keyboardF19: .f19
	]
}
#endif

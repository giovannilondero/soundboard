import Carbon

/// Key names accepted in config.json mapped to macOS virtual key codes (US/ABC layout).
enum KeyCodes {
    static let table: [String: UInt32] = {
        var t: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "`": kVK_ANSI_Grave, "\\": kVK_ANSI_Backslash,
            "space": kVK_Space, "tab": kVK_Tab, "return": kVK_Return, "escape": kVK_Escape,
            "delete": kVK_Delete, "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "up": kVK_UpArrow, "down": kVK_DownArrow,
        ]
        for i in 1...20 {
            let names = [1: kVK_F1, 2: kVK_F2, 3: kVK_F3, 4: kVK_F4, 5: kVK_F5, 6: kVK_F6, 7: kVK_F7,
                         8: kVK_F8, 9: kVK_F9, 10: kVK_F10, 11: kVK_F11, 12: kVK_F12, 13: kVK_F13,
                         14: kVK_F14, 15: kVK_F15, 16: kVK_F16, 17: kVK_F17, 18: kVK_F18, 19: kVK_F19,
                         20: kVK_F20]
            t["f\(i)"] = names[i]!
        }
        return t.mapValues { UInt32($0) }
    }()

    static func code(for name: String) -> UInt32? { table[name.lowercased()] }

    /// Hyper = ⌃⌥⇧⌘
    static let hyper: UInt32 = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    static func label(_ name: String) -> String {
        switch name.lowercased() {
        case "escape": return "⎋"
        case "space": return "␣"
        case "return": return "↩"
        case "tab": return "⇥"
        case "delete": return "⌫"
        default: return name.uppercased()
        }
    }
}

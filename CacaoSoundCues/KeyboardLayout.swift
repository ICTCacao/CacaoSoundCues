import CacaoSoundCuesCore
import Carbon
import Foundation

/// 画面に描くキーボード。キーはハードウェアのキーコードで持つ（入力ソースが日本語でも同じ）
enum KeyboardLayout {
    static let escape: UInt16 = 53
    static let space: UInt16 = 49
    /// リストの次の曲へ（固定）
    static let returnKey: UInt16 = 36
    static let enterKey: UInt16 = 76
    /// リストの「次に鳴らす曲」を上下に動かす（固定）
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125

    static let isJIS = KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardJIS

    static let rows: [[UInt16]] = isJIS
        ? [
            [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 93],
            [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30],
            [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42],
            [6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 94],
        ]
        : [
            [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
            [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
            [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
            [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
        ]

    /// 行ごとの左のずれ（キー幅に対する割合）
    static let rowIndent: [CGFloat] = isJIS ? [0, 0.5, 0.75, 1.25] : [0, 0.5, 0.75, 1.25]

    /// F1〜F12（設定で表示する）
    static let functionRow: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    /// テンキー（設定で表示する）。上の3段は4列、下の2段は「1 2 3 / 0(2列分) .」と縦長の enter
    static let keypadTopRows: [[UInt16]] = [[71, 81, 75, 67], [89, 91, 92, 78], [86, 87, 88, 69]]
    static let keypadRow123: [UInt16] = [83, 84, 85]
    static let keypadZero: UInt16 = 82
    static let keypadDecimal: UInt16 = 65
    static let keypadKeys: Set<UInt16> = Set(keypadTopRows.joined()).union(keypadRow123).union([keypadZero, keypadDecimal])

    /// 音やリストを割り当てられるキー（space は「リストの曲を終える」専用、テンキーの enter は「次の曲へ」）
    static let allKeys: Set<UInt16> = Set(rows.joined()).union(functionRow).union(keypadKeys)

    /// 入力ソースで変わらない表示名（F キーとテンキー。テンキーは上の段の数字と区別して「num」を付ける）
    private static let fixedLabels: [UInt16: String] = {
        var d: [UInt16: String] = [:]
        for (i, code) in functionRow.enumerated() { d[code] = "F\(i + 1)" }
        let pad: [UInt16: String] = [82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7",
                                     91: "8", 92: "9", 65: ".", 69: "+", 78: "-", 67: "*", 75: "/", 81: "="]
        for (code, s) in pad { d[code] = "num" + s }
        d[71] = "clear"
        d[enterKey] = "enter"
        return d
    }()

    /// macOS の設定「F1、F2 などのキーを標準のファンクションキーとして使用」が ON か
    static var functionKeysAreStandard: Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.keyboard.fnState"] as? NSNumber)?.boolValue ?? false
    }

    /// 操作用に固定していて割り当てられないキーなら、その理由
    static func reservedReason(_ code: UInt16) -> String? {
        switch code {
        case returnKey, enterKey: return L("Return キーは「リストの次の曲へ」に使うため割り当てられません")
        case space: return L("スペースキーは「リストの曲を途中で終える」に使うため割り当てられません")
        case escape: return L("Esc キーは「全停止」に使うため割り当てられません")
        default: return nil
        }
    }

    private static var cache: [UInt16: String] = [:]

    static func label(_ code: UInt16) -> String {
        if code == space { return "space" }
        if code == escape { return "esc" }
        if let s = fixedLabels[code] { return s }
        if let s = cache[code] { return s }
        let s = translate(code) ?? "#\(code)"
        cache[code] = s
        return s
    }

    private static func translate(_ code: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

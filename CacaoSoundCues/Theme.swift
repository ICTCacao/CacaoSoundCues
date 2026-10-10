import AppKit
import SwiftUI

/// 画面の色。ライトモードは薄いカカオ色、ダークモードは macOS 標準のまま。
/// アクセント色（選択・ボタン）は Assets の AccentColor（カカオブラウン）
enum Theme {
    /// ウィンドウ全体の地（キーボードの背景）
    static let background = dynamic(light: 0xEFE2D3, dark: nil, darkSystem: .windowBackgroundColor)
    /// 上の帯
    static let topBar = dynamic(light: 0xE2CDB8, dark: nil, darkSystem: .windowBackgroundColor)
    /// リスト・設定などの作業パネル
    static let panel = dynamic(light: 0xF6EDE3, dark: nil, darkSystem: .windowBackgroundColor)
    /// 割り当てていないキー
    static let keyEmpty = dynamic(light: 0xFBF6F0, dark: nil, darkSystem: .controlBackgroundColor)
    /// キーの枠線
    static let keyBorder = dynamic(light: 0xC2A189, dark: nil, darkSystem: NSColor.secondaryLabelColor.withAlphaComponent(0.4))
    /// 区切り線
    static let divider = dynamic(light: 0xD4BBA4, dark: nil, darkSystem: .separatorColor)

    private static func dynamic(light: UInt32, dark: UInt32?, darkSystem: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return dark.map(rgb) ?? darkSystem
            }
            return rgb(light)
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// 区切り線（Divider の代わりに Theme の色で）
struct ThemeDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}

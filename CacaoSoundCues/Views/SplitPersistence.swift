import AppKit
import SwiftUI

/// 分割画面（HSplitView）の仕切りの位置を、割合で覚えておいて次に開いたときに戻す（この Mac に保存）。
/// 分割画面のどれかの枠の .background に置く。key は画面の並びごとに変える
struct SplitPersistence: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> FinderView { FinderView(key: key) }
    func updateNSView(_ nsView: FinderView, context: Context) {}

    final class FinderView: NSView {
        let key: String
        private weak var split: NSSplitView?
        private var observer: NSObjectProtocol?
        private var restoring = false

        init(key: String) {
            self.key = key
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, split == nil else { return }
            // 画面が並び終わってから、外側の分割画面を探す
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.attach() }
        }

        private func attach() {
            var v: NSView? = superview
            while let cur = v, !(cur is NSSplitView) { v = cur.superview }
            guard let split = v as? NSSplitView else { return }
            self.split = split
            restore(split)
            observer = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification,
                                                              object: split, queue: .main) { [weak self] _ in
                self?.save()
            }
        }

        private func restore(_ split: NSSplitView) {
            // 数字で保存したもののほか、文字で渡されたもの（起動するときの指定など）も読む
            let raw = UserDefaults.standard.array(forKey: key) ?? []
            let fractions = raw.compactMap { ($0 as? NSNumber)?.doubleValue ?? Double($0 as? String ?? "") }
            guard fractions.count == raw.count,
                  fractions.count == split.subviews.count - 1, split.bounds.width > 0 else { return }
            restoring = true
            for (i, f) in fractions.enumerated() {
                split.setPosition(CGFloat(f) * split.bounds.width, ofDividerAt: i)
            }
            restoring = false
        }

        private func save() {
            guard !restoring, let split, split.bounds.width > 0, split.subviews.count > 1 else { return }
            let fractions = split.subviews.dropLast().map { Double($0.frame.maxX / split.bounds.width) }
            UserDefaults.standard.set(fractions, forKey: key)
        }
    }
}

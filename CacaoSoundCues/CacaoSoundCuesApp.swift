import AppKit
import SwiftUI

@main
struct CacaoSoundCuesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("showFunctionKeys") private var showFunctionKeys = false
    @AppStorage("showKeypad") private var showKeypad = false

    var body: some Scene {
        Window("CacaoSoundCues", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 1180, minHeight: 760)
        }
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("CacaoSoundCues について") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: AppModel.versionText,
                        .version: "",
                    ])
                }
            }
            CommandGroup(before: .toolbar) {
                Toggle("キーボードを表示", isOn: $showKeyboard)
                Toggle("F キー（F1〜F12）の行を表示", isOn: $showFunctionKeys)
                Toggle("テンキーを表示", isOn: $showKeypad)
                Divider()
            }
            CommandGroup(replacing: .newItem) {
                Button { model.newShow() } label: { Label("新規キューシート", systemImage: "doc.badge.plus") }
                    .keyboardShortcut("n")
                Button { model.openPanel() } label: { Label("開く…", systemImage: "folder") }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button { model.save() } label: { Label("保存", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s")
                Button { model.saveAs() } label: { Label("別名で保存…", systemImage: "square.and.arrow.down.on.square") }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppModel.shared.confirmQuit() } ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated {
            let model = AppModel.shared
            if model.confirmDiscard() { model.open(url) }
        }
    }
}

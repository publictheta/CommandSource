import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    /// ステータスバーに表示するメニュー。
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    /// キーイベントの合成器。
    lazy var composer = EventComposer()

    /// メッセージを表示するためのメニュー項目。
    var messageItem: NSMenuItem?

    /// ログイン項目のメニュー項目。
    var loginItem: NSMenuItem?

    /// アプリケーション起動後の処理。
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // ステータスバーに表示するメニューの作成
        statusItem.menu = createMenu()
        statusItem.button?.image = NSImage(
            systemSymbolName: "command",
            accessibilityDescription: "CommandSource"
        )

        // 権限の確認
        if checkTrusted() {
            // 権限が有効な場合、キーイベントの変換を開始
            composer.enable()
            messageItem?.isHidden = true
        } else {
            // 権限が無効な場合、メニューにメッセージを表示
            messageItem?.title = "アクセシビリティアクセスを有効にして再起動してください。"
            messageItem?.isHidden = false
        }
    }

    /// アプリケーション終了時の処理。
    func applicationWillTerminate(_ aNotification: Notification) {
        composer.disable()
    }

    /// アクセシビリティアクセスの権限を要求する。
    ///
    /// - Returns: 既にアクセスが許可されている場合は `true` を返す。
    private func checkTrusted() -> Bool {
        let options =
            [
                kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
            ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    /// バンドル名を取得する。
    private func getBundleName() -> String? {
        return Bundle.main.infoDictionary?["CFBundleName"] as? String
    }

    /// バンドルバージョンを取得する。
    private func getBundleVersion() -> String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// アプリケーション名を取得する。
    private func getAppName() -> String {
        return getBundleName() ?? "CommandSource"
    }

    /// アプリケーションの説明を取得する。
    private func getAppString() -> String {
        var string = getAppName()

        if let version = getBundleVersion() {
            string += " (ver. " + version + ")"
        }

        return string
    }

    /// ステータスバーのメニューを生成する。
    ///
    /// - Returns: ステータスバーに表示するメニュー。
    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(withTitle: getAppString(), action: nil, keyEquivalent: "")

        messageItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")

        menu.addItem(.separator())

        loginItem = menu.addItem(
            withTitle: "",
            action: #selector(AppDelegate.toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        updateLaunchAtLogin()

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "再起動",
            action: #selector(AppDelegate.relaunch(_:)),
            keyEquivalent: "r"
        )

        menu.addItem(
            withTitle: "終了",
            action: #selector(AppDelegate.quit(_:)),
            keyEquivalent: "q"
        )

        return menu
    }

    /// ログイン項目への登録状態の表示を更新する。
    private func updateLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            loginItem?.title = "ログイン項目から削除"
        } else {
            loginItem?.title = "ログイン項目に追加"
        }
    }

    /// ログイン項目への登録を切り替える。
    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        if SMAppService.mainApp.status == .enabled {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                print("[CommandSource]: Failed to unregister a login item. \(error)")
            }
        } else {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("[CommandSource]: Failed to register a login item. \(error)")
            }
        }

        updateLaunchAtLogin()
    }

    /// アプリケーションを再起動する。
    @objc func relaunch(_ sender: Any?) {
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        try! process.run()
        NSApplication.shared.terminate(self)
    }

    /// アプリケーションを終了する。
    @objc func quit(_ sender: Any?) {
        NSApplication.shared.terminate(self)
    }
}

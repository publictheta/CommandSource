import Carbon
import Cocoa

/// 左コマンドキーのキーコード。
private let COMMAND_LEFT: Int64 = Int64(kVK_Command)
/// 右コマンドキーのキーコード。
private let COMMAND_RIGHT: Int64 = Int64(kVK_RightCommand)

/// キーイベントの合成器。
///
/// イベントタップはメインスレッドの実行ループで処理するため、メインアクターに隔離する。
@MainActor
class EventComposer {
    /// キーの押下と長押しを区別する閾値。押下の場合のみ、英数・かなキーのイベントを発火する。
    ///
    /// `300 * 1000 * 1000 ns = 300 ms`
    private let threshold: CGEventTimestamp = 300 * 1000 * 1000

    /// イベントタップ。
    private var tap: CFMachPort?
    /// 入力ソース。
    private var source: CFRunLoopSource?

    /// 最後に左コマンドキーがkeydownされた時のタイムスタンプ。
    private var left: CGEventTimestamp?
    /// 最後に右コマンドキーがkeydownされた時のタイムスタンプ。
    private var right: CGEventTimestamp?

    /// キー変換の状態をリセットする。
    private func clear() {
        self.left = nil
        self.right = nil
    }

    /// コマンドキーのイベントを処理する。
    private func handleCommands(_ event: CGEvent) {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keycode {
        case COMMAND_LEFT:
            if event.flags.contains(.maskLeftCommand) {
                if self.left == nil {
                    // keydownとみなす
                    self.left = event.timestamp
                }
            } else {
                if let left = self.left {
                    // 閾値以下の間隔でkeyupが発生した場合、英数キーを押す
                    if event.timestamp - left < self.threshold {
                        press(.jisEisu)
                    }

                    // keyupとみなす
                    self.left = nil
                }
            }
        case COMMAND_RIGHT:
            if event.flags.contains(.maskRightCommand) {
                if self.right == nil {
                    // keydownとみなす
                    self.right = event.timestamp
                }
            } else {
                if let right = self.right {
                    // 閾値以下の間隔でkeyupが発生した場合、かなキーを押す
                    if event.timestamp - right < self.threshold {
                        press(.jisKana)
                    }

                    // keyupとみなす
                    self.right = nil
                }
            }
        default:
            break
        }
    }

    /// イベントを処理する。
    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // スリープ等により無効になった状態から復帰する。
            guard let tap = self.tap else {
                print("[CommandSource]: The previous tap not found.")
                exit(1)
            }

            clear()

            enableTap(tap)
        case .flagsChanged:
            // Commandキーの上下を検知する。
            handleCommands(event)
        case .keyDown:
            // Command + ? が発生したとみなす。
            clear()
        default:
            break
        }
    }

    /// 指定されたキーコードのキーを押す（keydown + keyup）。
    private func press(_ keyCode: CGKeyCode) {
        guard let keydown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        else {
            return
        }

        guard let keyup = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        keydown.flags = .maskNonCoalesced
        keyup.flags = .maskNonCoalesced

        keydown.post(tap: .cghidEventTap)
        keyup.post(tap: .cghidEventTap)
    }

    /// イベントタップを作成する。
    ///
    /// イベントを書き換えたり握りつぶしたりはしないので、listen-only（受動）タップにする。
    /// 受動タップならOSはこのアプリの応答を待たないため、キー入力の遅延を引き起こさない。
    private func createTap() -> CFMachPort? {
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: .fromTypes(.flagsChanged, .keyDown),
            callback: { _, type, event, refcon in
                if let refcon = refcon {
                    // タップはメインスレッドの実行ループに登録しているので、常にメインスレッドで呼ばれる。
                    MainActor.assumeIsolated {
                        Unmanaged<EventComposer>.fromOpaque(refcon).takeUnretainedValue()
                            .handle(type, event)
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// イベントタップを有効にする。
    private func enableTap(_ tap: CFMachPort) {
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// イベントタップを無効にする。
    private func disableTap(_ tap: CFMachPort) {
        CGEvent.tapEnable(tap: tap, enable: false)
    }

    /// 入力ソースを作成する。
    private func createSource(_ tap: CFMachPort) -> CFRunLoopSource? {
        return CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    }

    /// 入力ソースをメインスレッドの実行ループに追加する。
    private func addSource(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
    }

    /// 入力ソースを削除する。
    private func removeSource(_ source: CFRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CFRunLoopSourceInvalidate(source)
    }

    /// キーイベントの変換を有効にする。
    func enable() {
        guard let tap = createTap() else {
            print("[CommandSource]: Failed to create a tap.")
            exit(1)
        }

        guard let source = createSource(tap) else {
            print("[CommandSource]: Failed to create a run loop source.")
            exit(1)
        }

        addSource(source)
        enableTap(tap)

        self.tap = tap
        self.source = source

        print("[CommandSource]: Enabled.")
    }

    /// キーイベントの変換を無効にする。
    func disable() {
        if let tap = self.tap {
            disableTap(tap)
        }

        if let source = self.source {
            removeSource(source)
        }

        self.tap = nil
        self.source = nil

        print("[CommandSource]: Disabled.")
    }
}

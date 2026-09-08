import Carbon
import Cocoa

/// キーイベントの合成器。
///
/// イベントタップはメインスレッドの実行ループで処理するため、メインアクターに隔離する。
@MainActor
class EventComposer {
    /// 左コマンドキーのキーコード。
    private static let commandLeft = Int64(kVK_Command)
    /// 右コマンドキーのキーコード。
    private static let commandRight = Int64(kVK_RightCommand)

    /// 左コマンドキーが押されていることを表すフラグ（非公開ビットを含む）。
    private static let maskCommandLeft = CGEventFlags(rawValue: 0x10_0008)
    /// 右コマンドキーが押されていることを表すフラグ（非公開ビットを含む）。
    private static let maskCommandRight = CGEventFlags(rawValue: 0x10_0010)

    /// 英数キーのキーコード。
    private static let jisEisu = CGKeyCode(kVK_JIS_Eisu)
    /// かなキーのキーコード。
    private static let jisKana = CGKeyCode(kVK_JIS_Kana)

    /// キーの押下と長押しを区別する閾値。押下の場合のみ、英数・かなキーのイベントを発火する。
    ///
    /// `300 * 1000 * 1000 ns = 300 ms`
    private static let threshold: CGEventTimestamp = 300 * 1000 * 1000

    /// イベントタップ。
    private var tap: CFMachPort?

    /// 最後に左コマンドキーがkeydownされた時のタイムスタンプ。
    private var left: CGEventTimestamp?
    /// 最後に右コマンドキーがkeydownされた時のタイムスタンプ。
    private var right: CGEventTimestamp?

    /// キー変換の状態をリセットする。
    private func clear() {
        left = nil
        right = nil
    }

    /// コマンドキーのイベントを処理する。
    private func handleCommands(_ event: CGEvent) {
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case Self.commandLeft:
            if event.flags.contains(Self.maskCommandLeft) {
                if left == nil {
                    // keydownとみなす
                    left = event.timestamp
                }
            } else if let left {
                // 閾値以下の間隔でkeyupが発生した場合、英数キーを押す
                if event.timestamp - left < Self.threshold {
                    press(Self.jisEisu)
                }

                // keyupとみなす
                self.left = nil
            }
        case Self.commandRight:
            if event.flags.contains(Self.maskCommandRight) {
                if right == nil {
                    // keydownとみなす
                    right = event.timestamp
                }
            } else if let right {
                // 閾値以下の間隔でkeyupが発生した場合、かなキーを押す
                if event.timestamp - right < Self.threshold {
                    press(Self.jisKana)
                }

                // keyupとみなす
                self.right = nil
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
            clear()

            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
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
        for keyDown in [true, false] {
            guard
                let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
            else {
                return
            }

            event.flags = .maskNonCoalesced
            event.post(tap: .cghidEventTap)
        }
    }

    /// キーイベントの変換を有効にする。
    ///
    /// イベントを書き換えたり握りつぶしたりはしないので、listen-only（受動）タップにする。
    /// 受動タップならOSはこのアプリの応答を待たないため、キー入力の遅延を引き起こさない。
    func enable() {
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: 1 << CGEventType.flagsChanged.rawValue | 1
                << CGEventType.keyDown.rawValue,
            callback: { _, type, event, refcon in
                if let refcon {
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

        guard let tap else {
            print("[CommandSource]: Failed to create a tap.")
            exit(1)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0),
            .commonModes
        )
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
    }
}

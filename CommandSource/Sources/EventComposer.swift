import Carbon
import Cocoa

/// 左コマンドキーのキーコード。
private let COMMAND_LEFT: Int64 = Int64(kVK_Command)
/// 右コマンドキーのキーコード。
private let COMMAND_RIGHT: Int64 = Int64(kVK_RightCommand)

/// キーイベントの合成器。
class EventComposer: NSObject {
    /// ポインタからインスタンスを作成する。
    ///
    static func fromOpaque(_ pointer: UnsafeMutableRawPointer) -> Self {
        Unmanaged<Self>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// キーの押下と長押しを区別する閾値。押下の場合のみ、英数・かなキーのイベントを発火する。
    ///
    /// `300 * 1000 * 1000 ns = 300 ms`
    private var threshold: CGEventTimestamp = 300 * 1000 * 1000

    /// イベントタップ。
    private var tap: CFMachPort?
    /// 入力ソース。
    private var source: CFRunLoopSource?

    /// 最後に左コマンドキーがkeydownされた時のタイムスタンプ。
    private var left: CGEventTimestamp?
    /// 最後に右コマンドキーがkeydownされた時のタイムスタンプ。
    private var right: CGEventTimestamp?

    /// キー変換の状態をリセットする。
    ///
    private func clear() {
        self.left = nil
        self.right = nil
    }

    /// コマンドキーのイベントを処理する。
    private func handleCommands(_ event: CGEvent, _ proxy: CGEventTapProxy) {
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
                        press(.jisEisu, proxy)
                    }

                    // keyupとみなす
                    self.left = nil
                }
            }
            break
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
                        press(.jisKana, proxy)
                    }

                    // keyupとみなす
                    self.right = nil
                }
            }
            break
        default:
            break
        }
    }

    /// イベントを処理する。
    private func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> CGEvent?
    {
        switch type {
        case .tapDisabledByTimeout:
            // スリープ等により無効になった状態から復帰する。

            guard let tap = self.tap else {
                print("[CommandSource]: The previous tap not found.")
                exit(1)
                break
            }

            clear()

            enableTap(tap)
        case .flagsChanged:
            // Commandキーの上下を検知する。
            handleCommands(event, proxy)
        case .keyDown:
            // Command + ? が発生したとみなす。
            clear()
        default:
            break
        }

        return event
    }

    /// 指定されたキーコードのキーを押す（keydown + keyup）。
    private func press(_ keyCode: CGKeyCode, _ proxy: CGEventTapProxy) {
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

        keydown.tapPostEvent(proxy)
        keyup.tapPostEvent(proxy)
    }

    /// イベントタップを作成する。x
    private func createTap() -> CFMachPort? {
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: .fromTypes(.flagsChanged, .keyDown),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }

                return EventComposer.fromOpaque(refcon).handle(proxy, type, event).map {
                    (event) -> Unmanaged<CGEvent> in
                    Unmanaged.passUnretained(event)
                }
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
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

    /// 入力ソースを現在の実行ループに追加する。
    private func addSource(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
    }

    /// 入力ソースを削除する。
    private func removeSource(_ source: CFRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
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

import Cocoa

extension CGEventFlags {
    // left command: 1048840  = 100000000000100001000
    // right command: 1048848 = 100000000000100010000
    // none: 256              =             100000000

    // maskCommand: 1048576   = 100000000000000000000
    // maskNonCoalesced: 256  =             100000000

    /// 左コマンドキーを表すマスク。
    static let maskLeftCommand = CGEventFlags(rawValue: 0b10000_00000000_00001000)

    /// 右コマンドキーを表すマスク。
    static let maskRightCommand = CGEventFlags(rawValue: 0b10000_00000000_00010000)
}

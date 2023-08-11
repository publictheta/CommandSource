import Cocoa

extension CGEventMask {
    /// `CGEventMask` を `CGEventType` から作成する。
    static func fromTypes(_ types: CGEventType...) -> Self {
        var mask = 0

        for type in types {
            mask |= (1 << type.rawValue)
        }

        return Self(mask)
    }
}

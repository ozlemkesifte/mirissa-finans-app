import Foundation

public enum IdPrefix: String {
    case material = "mat"
    case product = "pro"
    case sale = "sal"
    case expense = "exp"
    case purchase = "pur"
    case adjustment = "adj"
    case count = "cnt"
    case channel = "chn"
    case channelMonth = "chm"
    case costLine = "cst"
    case recipeLine = "rcp"
    case balance = "bal"
    case price = "prc"
    case channelFee = "cfe"
    case channelRate = "crt"
}

public enum Ids {
    nonisolated(unsafe) private static var counter: UInt64 = 0
    private static let lock = NSLock()

    /// "mat_lq3k9f_1a2b" — ön ek hata ayıklamayı kolaylaştırır,
    /// sayaç aynı milisaniyedeki kayıtların sırasını korur.
    public static func make(_ prefix: IdPrefix) -> String {
        lock.lock()
        counter &+= 1
        let c = counter
        lock.unlock()
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        let rand = UInt32.random(in: 0..<46656) // 3 hane base36
        return "\(prefix.rawValue)_\(String(ms, radix: 36))_\(String(c, radix: 36))\(String(rand, radix: 36))"
    }
}

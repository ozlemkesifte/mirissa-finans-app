import Foundation

/// Para birimi: her yerde tam sayı **kuruş**. 141,00 TL == 14100
public typealias Kurus = Int

public enum Money {
    /// 141.50 -> 14150
    public static func fromTL(_ tl: Double) -> Kurus {
        roundHalfAwayFromZero(tl * 100)
    }

    public static func toTL(_ k: Kurus) -> Double {
        Double(k) / 100
    }

    public static func roundHalfAwayFromZero(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return v < 0 ? -Int((-v).rounded(.toNearestOrAwayFromZero))
                     : Int(v.rounded(.toNearestOrAwayFromZero))
    }

    /// Türkçe para biçimi: 185.000 TL / 1.234,56 TL
    public static func format(_ k: Kurus, showKurus: Bool = false, withSymbol: Bool = true) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        let hasKurus = showKurus || (k % 100 != 0)
        f.minimumFractionDigits = hasKurus ? 2 : 0
        f.maximumFractionDigits = hasKurus ? 2 : 0
        let n = NSNumber(value: toTL(k))
        let body = f.string(from: n) ?? "0"
        return withSymbol ? "\(body) TL" : body
    }

    /// Büyük kartlar için kısa biçim: 185.000 TL, 1,85 Mn TL
    public static func formatCompact(_ k: Kurus) -> String {
        let abs = Swift.abs(k)
        if abs >= 100_000_000 { // >= 1 milyon TL
            let mn = Double(k) / 100_000_000
            return "\(decimal(mn, digits: mn.magnitude >= 10 ? 1 : 2)) Mn TL"
        }
        return format(k)
    }

    private static func decimal(_ v: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    /// %28,6
    public static func formatPercent(_ pct: Double, digits: Int = 1) -> String {
        guard pct.isFinite else { return "%0" }
        return "%" + decimal(pct, digits: digits)
    }
}

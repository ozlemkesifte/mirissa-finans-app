import Foundation

public enum Dimension: String, Codable, Sendable, CaseIterable {
    case count, mass, volume, length
}

/// Stok birimleri. `adet/gram/ml/cm` temel birimlerdir; diğerleri bunlara çevrilir.
/// `rulo/paket/kutu/koli` kap birimleridir — kaç temel birim ettiği malzemeye göre değişir.
public enum UnitCode: String, Codable, Sendable, CaseIterable, Identifiable {
    case adet, kg, gram, litre, ml, metre, cm, rulo, paket, kutu, koli

    public var id: String { rawValue }

    public var dimension: Dimension {
        switch self {
        case .kg, .gram: return .mass
        case .litre, .ml: return .volume
        case .metre, .cm: return .length
        case .adet, .rulo, .paket, .kutu, .koli: return .count
        }
    }

    /// Kaç temel birim eder. `nil` ise malzemenin `packSizes` tanımına bakılır.
    public var fixedFactor: Double? {
        switch self {
        case .adet: return 1
        case .gram: return 1
        case .kg: return 1000
        case .ml: return 1
        case .litre: return 1000
        case .cm: return 1
        case .metre: return 100
        case .rulo, .paket, .kutu, .koli: return nil
        }
    }

    public var isContainer: Bool { fixedFactor == nil }

    public var isBaseUnit: Bool {
        self == .adet || self == .gram || self == .ml || self == .cm
    }

    public static func baseUnit(for d: Dimension) -> UnitCode {
        switch d {
        case .count: return .adet
        case .mass: return .gram
        case .volume: return .ml
        case .length: return .cm
        }
    }

    public var displayName: String {
        switch self {
        case .adet: return "adet"
        case .kg: return "kg"
        case .gram: return "gram"
        case .litre: return "litre"
        case .ml: return "ml"
        case .metre: return "metre"
        case .cm: return "cm"
        case .rulo: return "rulo"
        case .paket: return "paket"
        case .kutu: return "kutu"
        case .koli: return "koli"
        }
    }

    /// Kullanıcıya gösterilen kısa birim (temel birimden türetilmiş görünüm için)
    public var shortName: String { displayName }
}

/// Temel birim cinsinden miktar (adet / gram / ml / cm)
public typealias BaseQty = Double

public enum UnitError: Error, CustomStringConvertible, Equatable {
    case dimensionMismatch(unit: UnitCode, itemBase: UnitCode)
    case missingPackSize(unit: UnitCode, itemName: String)

    public var description: String {
        switch self {
        case let .dimensionMismatch(u, b):
            return "\(u.displayName) birimi, \(b.displayName) ile ölçülen bir kalem için kullanılamaz."
        case let .missingPackSize(u, n):
            return "\(n) için 1 \(u.displayName) kaç \(u.displayName == "koli" ? "adet" : "birim") eder tanımlı değil."
        }
    }
}

public enum Units {
    /// Girilen miktarı kalemin temel birimine çevirir.
    /// Kap birimleri (paket/kutu/koli/rulo) için `packSizes` gerekir.
    public static func toBase(
        qty: Double,
        unit: UnitCode,
        baseUnit: UnitCode,
        packSizes: [UnitCode: Double]
    ) throws -> BaseQty {
        if let f = unit.fixedFactor {
            guard unit.dimension == baseUnit.dimension else {
                throw UnitError.dimensionMismatch(unit: unit, itemBase: baseUnit)
            }
            return qty * f
        }
        guard let size = packSizes[unit], size > 0 else {
            throw UnitError.missingPackSize(unit: unit, itemName: "")
        }
        return qty * size
    }

    /// Hataları yutan, ölçü uyuşmazlığında `nil` dönen yumuşak sürüm.
    public static func toBaseOrNil(
        qty: Double,
        unit: UnitCode,
        baseUnit: UnitCode,
        packSizes: [UnitCode: Double]
    ) -> BaseQty? {
        try? toBase(qty: qty, unit: unit, baseUnit: baseUnit, packSizes: packSizes)
    }

    /// Bir kalem için seçilebilecek birimler: kendi boyutundakiler + tanımlı kap birimleri.
    public static func allowedUnits(baseUnit: UnitCode, packSizes: [UnitCode: Double]) -> [UnitCode] {
        var out = UnitCode.allCases.filter { !$0.isContainer && $0.dimension == baseUnit.dimension }
        out += UnitCode.allCases.filter { $0.isContainer && (packSizes[$0] ?? 0) > 0 }
        return out
    }

    /// Birimsiz sayı: 2 -> "2", 0,5 -> "0,5"
    public static func formatNumber(_ v: Double, digits: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    /// Temel birimdeki miktarı okunur biçimde yazar: 1200 gram -> "1,2 kg", 70 -> "70 adet"
    public static func formatQty(_ base: BaseQty, baseUnit: UnitCode, forceBase: Bool = false) -> String {
        func num(_ v: Double, _ digits: Int) -> String {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = Locale(identifier: "tr_TR")
            f.groupingSeparator = "."
            f.decimalSeparator = ","
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = digits
            return f.string(from: NSNumber(value: v)) ?? "0"
        }
        if forceBase {
            return "\(num(base, 2)) \(baseUnit.displayName)"
        }
        switch baseUnit {
        case .gram:
            if Swift.abs(base) >= 1000 { return "\(num(base / 1000, 2)) kg" }
            return "\(num(base, 0)) gram"
        case .ml:
            if Swift.abs(base) >= 1000 { return "\(num(base / 1000, 2)) litre" }
            return "\(num(base, 0)) ml"
        case .cm:
            if Swift.abs(base) >= 100 { return "\(num(base / 100, 2)) metre" }
            return "\(num(base, 0)) cm"
        default:
            return "\(num(base, base == base.rounded() ? 0 : 2)) adet"
        }
    }
}
